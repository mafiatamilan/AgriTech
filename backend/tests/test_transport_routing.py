from datetime import datetime, timezone, timedelta

import pytest

from app.agents.transport_routing import (
    TransportOrder,
    VehicleProfile,
    estimate_distance_km,
    recommend_transport_routes,
)


def test_distance_estimator_uses_coordinates():
    distance = estimate_distance_km(
        {"latitude": 18.52, "longitude": 73.85},
        {"latitude": 19.07, "longitude": 72.88},
    )
    assert 120 < distance < 180


def test_returns_fastest_cheapest_and_safest_without_internal_score():
    order = TransportOrder(
        pickup_location={"latitude": 18.52, "longitude": 73.85},
        delivery_location={"latitude": 19.07, "longitude": 72.88},
        crop="spinach",
        quantity_kg=100,
        vehicle=VehicleProfile("refrigerated_van", 500, 20, True),
        route_candidates=[
            {"route_id": "fast", "label": "Highway", "distance_km": 160, "estimated_time_hours": 3, "transport_cost": 4000},
            {"route_id": "cheap", "label": "Local roads", "distance_km": 130, "estimated_time_hours": 6, "transport_cost": 2200},
            {"route_id": "safe", "label": "Expressway", "distance_km": 175, "estimated_time_hours": 4, "transport_cost": 3500},
        ],
    )
    result = recommend_transport_routes(order)
    assert result.best_route["route_id"] == "fast"
    assert len(result.route_options) == 3
    assert all("internal_score" not in option for option in result.route_options)
    assert "internal_score" not in result.best_route


def test_sensitive_crop_flags_non_refrigerated_vehicle_and_delivery_window():
    order = TransportOrder(
        pickup_location={"latitude": 18.52, "longitude": 73.85},
        delivery_location={"latitude": 19.07, "longitude": 72.88},
        crop="spinach",
        quantity_kg=1200,
        vehicle=VehicleProfile("small_truck", 500, 15, False),
        harvest_time=datetime.now(timezone.utc),
        required_delivery_time=datetime.now(timezone.utc) + timedelta(hours=2),
        current_weather={"condition": "heavy rain", "wind_speed_kmph": 45},
        route_candidates=[{"route_id": "r1", "distance_km": 150, "estimated_time_hours": 5}],
    )
    result = recommend_transport_routes(order)
    assert result.spoilage_risk == "high"
    assert result.delay_risk == "high"
    assert any("cold-chain" in label for label in result.reason_labels)
    assert any("capacity" in label for label in result.reason_labels)
