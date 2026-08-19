"""Rule-based transport routing agent.

The agent deliberately has no maps/traffic dependency.  Callers may provide
route_candidates from a real routing provider later; the scoring and output
contract stays the same.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from math import asin, cos, radians, sin, sqrt
from typing import Any


@dataclass
class VehicleProfile:
    vehicle_type: str = "small_truck"
    capacity_kg: float = 1000.0
    cost_per_km: float = 15.0
    refrigerated: bool = False


@dataclass
class TransportOrder:
    pickup_location: dict[str, Any]
    delivery_location: dict[str, Any]
    crop: str
    quantity_kg: float
    harvest_time: datetime | None = None
    required_delivery_time: datetime | None = None
    vehicle: VehicleProfile = field(default_factory=VehicleProfile)
    current_weather: dict[str, Any] = field(default_factory=dict)
    route_candidates: list[dict[str, Any]] = field(default_factory=list)
    shelf_life_hours: float | None = None


@dataclass
class RouteOption:
    route_id: str
    label: str
    distance_km: float
    estimated_time_hours: float
    estimated_transport_cost: float
    spoilage_risk: str
    delay_risk: str
    reason_labels: list[str]
    vehicle_capacity_fit: bool
    internal_score: float = 0.0


@dataclass
class TransportRouteRecommendation:
    best_route: dict[str, Any]
    route_options: list[dict[str, Any]]
    estimated_distance_km: float
    estimated_duration_minutes: int
    estimated_transport_cost: float
    spoilage_risk: str
    delay_risk: str
    reason_labels: list[str]


CROP_TRANSPORT_RULES: dict[str, dict[str, Any]] = {
    "spinach": {"max_hours": 8.0, "temperature_sensitive": True, "damage_risk": 0.9, "preferred": {"refrigerated_van", "reefer_truck"}},
    "tomato": {"max_hours": 18.0, "temperature_sensitive": True, "damage_risk": 0.6, "preferred": {"refrigerated_van", "small_truck"}},
    "potato": {"max_hours": 72.0, "temperature_sensitive": False, "damage_risk": 0.25, "preferred": {"small_truck", "large_truck"}},
    "rice": {"max_hours": 120.0, "temperature_sensitive": False, "damage_risk": 0.1, "preferred": {"small_truck", "large_truck"}},
    "wheat": {"max_hours": 120.0, "temperature_sensitive": False, "damage_risk": 0.1, "preferred": {"small_truck", "large_truck"}},
}
DEFAULT_CROP_RULE = {"max_hours": 48.0, "temperature_sensitive": False, "damage_risk": 0.4, "preferred": {"small_truck"}}


def _crop_rule(crop: str) -> dict[str, Any]:
    return CROP_TRANSPORT_RULES.get(crop.strip().lower(), DEFAULT_CROP_RULE)


def _coordinates(location: dict[str, Any]) -> tuple[float, float] | None:
    lat = location.get("latitude", location.get("lat"))
    lon = location.get("longitude", location.get("lon", location.get("lng")))
    if lat is None or lon is None:
        return None
    return float(lat), float(lon)


def estimate_distance_km(pickup: dict[str, Any], delivery: dict[str, Any]) -> float:
    """Estimate straight-line distance, inflated to approximate road travel."""
    a, b = _coordinates(pickup), _coordinates(delivery)
    if not a or not b:
        return 0.0
    lat1, lon1, lat2, lon2 = map(radians, (*a, *b))
    haversine = 2 * 6371.0 * asin(sqrt(sin((lat2 - lat1) / 2) ** 2 + cos(lat1) * cos(lat2) * sin((lon2 - lon1) / 2) ** 2))
    return round(haversine * 1.2, 2)


def _risk_level(value: float) -> str:
    return "high" if value >= 0.67 else "medium" if value >= 0.34 else "low"


def _weather_risk(weather: dict[str, Any]) -> tuple[float, list[str]]:
    risk = 0.0
    labels: list[str] = []
    condition = str(weather.get("condition", "")).lower()
    precipitation = float(weather.get("precipitation_mm", weather.get("rainfall_mm", 0)) or 0)
    wind = float(weather.get("wind_speed_kmph", 0) or 0)
    if any(word in condition for word in ("storm", "thunder", "flood", "heavy rain")) or precipitation > 25:
        risk += 0.7
        labels.append("adverse weather may delay delivery")
    elif precipitation > 5 or "rain" in condition:
        risk += 0.35
        labels.append("rain may slow the route")
    if wind > 35:
        risk += 0.25
        labels.append("strong winds increase delay risk")
    return min(risk, 1.0), labels


def _candidate(order: TransportOrder, raw: dict[str, Any], index: int) -> RouteOption:
    rule = _crop_rule(order.crop)
    distance = float(raw.get("distance_km") or estimate_distance_km(order.pickup_location, order.delivery_location))
    duration = float(raw.get("estimated_time_hours") or (float(raw.get("duration_minutes")) / 60 if raw.get("duration_minutes") is not None else distance / 35.0))
    duration = max(duration, 0.0)
    cost = float(raw.get("estimated_transport_cost") or raw.get("transport_cost") or distance * order.vehicle.cost_per_km)
    weather_value, reasons = _weather_risk(order.current_weather)
    capacity_fit = order.quantity_kg <= order.vehicle.capacity_kg
    score = min(distance / 300.0, 1.0) * 0.2 + min(duration / max(rule["max_hours"], 1), 1.0) * 0.3
    score += weather_value * 0.15 + rule["damage_risk"] * min(duration / max(rule["max_hours"], 1), 1) * 0.2
    if order.vehicle.vehicle_type not in rule["preferred"]:
        score += 0.1
        reasons.append(f"{order.crop} prefers a different vehicle type")
    if not capacity_fit:
        score += 0.35
        reasons.append("vehicle capacity is below shipment quantity")
    if order.required_delivery_time and order.harvest_time:
        available = (order.required_delivery_time - order.harvest_time).total_seconds() / 3600
        if duration > available:
            score += 0.35
            reasons.append("estimated route exceeds the delivery window")
    remaining_shelf_life = order.shelf_life_hours
    if remaining_shelf_life is not None and order.harvest_time:
        harvest_time = order.harvest_time
        if harvest_time.tzinfo is None:
            harvest_time = harvest_time.replace(tzinfo=timezone.utc)
        remaining_shelf_life -= max(0.0, (datetime.now(timezone.utc) - harvest_time).total_seconds() / 3600)
    if remaining_shelf_life is not None:
        if duration > max(remaining_shelf_life, 0):
            score += 0.4
            reasons.append("estimated route exceeds remaining shelf life")
        elif duration > max(remaining_shelf_life * 0.7, 0):
            score += 0.15
            reasons.append("shipment has an urgent remaining shelf-life window")
    if rule["temperature_sensitive"] and not order.vehicle.refrigerated:
        score += 0.2
        reasons.append("temperature-sensitive crop needs cold-chain protection")
    if duration > rule["max_hours"]:
        reasons.append("route exceeds the crop transport limit")
    if not reasons:
        reasons.append("route fits crop, vehicle, and delivery constraints")
    return RouteOption(
        route_id=str(raw.get("route_id") or f"route-{index + 1}"),
        label=str(raw.get("label") or f"Route {index + 1}"),
        distance_km=round(distance, 2),
        estimated_time_hours=round(duration, 2),
        estimated_transport_cost=round(cost, 2),
        spoilage_risk=_risk_level(min(rule["damage_risk"] + duration / max(rule["max_hours"], 1) + (0.2 if not capacity_fit else 0), 1.0)),
        delay_risk=_risk_level(min(duration / max(rule["max_hours"], 1) + weather_value + (0.2 if not capacity_fit else 0), 1.0)),
        reason_labels=reasons,
        vehicle_capacity_fit=capacity_fit,
        internal_score=round(score, 4),
    )


def recommend_transport_routes(order: TransportOrder) -> TransportRouteRecommendation:
    """Return up to three scored options; internal scores never leave this module."""
    candidates = order.route_candidates or [{}]
    options = [_candidate(order, raw, i) for i, raw in enumerate(candidates)]
    ranked = sorted(options, key=lambda option: option.internal_score)
    best = ranked[0]
    fastest = min(options, key=lambda option: option.estimated_time_hours)
    cheapest = min(options, key=lambda option: option.estimated_transport_cost)
    safest = min(options, key=lambda option: (option.spoilage_risk != "low", option.internal_score))
    selected: list[RouteOption] = []
    for option, label in ((fastest, "fastest route"), (cheapest, "lowest cost route"), (safest, "lowest spoilage-risk route")):
        if option not in selected:
            option.label = f"{option.label} ({label})"
            selected.append(option)
    for option in ranked:
        if len(selected) >= 3:
            break
        if option not in selected:
            selected.append(option)
    output = [asdict(option) for option in selected[:3]]
    for item in output:
        item.pop("internal_score", None)
    best_output = asdict(best)
    best_output.pop("internal_score", None)
    return TransportRouteRecommendation(
        best_route=best_output,
        route_options=output,
        estimated_distance_km=best.distance_km,
        estimated_duration_minutes=round(best.estimated_time_hours * 60),
        estimated_transport_cost=best.estimated_transport_cost,
        spoilage_risk=best.spoilage_risk,
        delay_risk=best.delay_risk,
        reason_labels=best.reason_labels,
    )
