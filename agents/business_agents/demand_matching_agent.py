from __future__ import annotations

from .crop_profiles import normalize_crop_name
from .models import BuyerDemand, BuyerOption, DemandMatchResult, InventoryStatus, Urgency, WeatherSnapshot


URGENCY_WEIGHT: dict[Urgency, float] = {
    Urgency.LOW: 0.2,
    Urgency.MEDIUM: 0.45,
    Urgency.HIGH: 0.7,
    Urgency.URGENT: 1.0,
    Urgency.EXPIRED_RISK: 1.0,
}


class DemandMatchingAgent:
    def recommend_top_matches(
        self,
        inventory: InventoryStatus,
        buyer_demands: list[BuyerDemand],
        transport_weather: WeatherSnapshot | None = None,
        limit: int = 3,
    ) -> DemandMatchResult:
        crop_key = normalize_crop_name(inventory.crop)
        candidates = [
            demand
            for demand in buyer_demands
            if normalize_crop_name(demand.crop) == crop_key
            and demand.quantity_requested_kg > 0
            and demand.transport_available
        ]

        if not candidates:
            return DemandMatchResult(
                crop=inventory.crop,
                batch_id=inventory.batch_id,
                quantity_available_kg=inventory.quantity_kg,
                urgency=inventory.shelf_life.urgency,
                top_matches=tuple(),
                message="No active buyer demand found for this crop.",
            )

        max_price = max(demand.offered_price_per_kg for demand in candidates)
        ranked = [
            (self._score(inventory, demand, max_price, transport_weather), demand)
            for demand in candidates
        ]
        ranked.sort(key=lambda item: item[0], reverse=True)

        options = tuple(
            self._to_farmer_option(rank=index + 1, inventory=inventory, demand=demand)
            for index, (_, demand) in enumerate(ranked[:limit])
        )

        return DemandMatchResult(
            crop=inventory.crop,
            batch_id=inventory.batch_id,
            quantity_available_kg=inventory.quantity_kg,
            urgency=inventory.shelf_life.urgency,
            top_matches=options,
            message="Top buyer options ranked for farmer choice.",
        )

    def _score(
        self,
        inventory: InventoryStatus,
        demand: BuyerDemand,
        max_price: float,
        transport_weather: WeatherSnapshot | None,
    ) -> float:
        urgency = URGENCY_WEIGHT[inventory.shelf_life.urgency]
        price_score = demand.offered_price_per_kg / max(max_price, 1)
        quantity_fit = min(demand.quantity_requested_kg, inventory.quantity_kg) / max(inventory.quantity_kg, 1)
        distance_score = 1 / (1 + demand.distance_km / 12)
        pickup_speed = 1 / (1 + demand.pickup_in_hours / 24)
        reliability = max(0.0, min(1.0, demand.buyer_reliability))
        transport_risk = (transport_weather.transport_risk if transport_weather else 0.0)
        rain_risk = min(0.25, ((transport_weather.rainfall_mm if transport_weather else 0.0) / 60))

        return (
            price_score * 0.28
            + quantity_fit * 0.22
            + distance_score * (0.16 + urgency * 0.08)
            + pickup_speed * (0.14 + urgency * 0.1)
            + reliability * 0.16
            - transport_risk * 0.12
            - rain_risk
        )

    def _to_farmer_option(
        self,
        rank: int,
        inventory: InventoryStatus,
        demand: BuyerDemand,
    ) -> BuyerOption:
        quantity_to_sell = min(inventory.quantity_kg, demand.quantity_requested_kg)
        reasons = self._reason_labels(inventory, demand, quantity_to_sell)
        recommendation = self._recommendation_text(inventory, demand)

        return BuyerOption(
            rank=rank,
            buyer_id=demand.buyer_id,
            buyer_name=demand.buyer_name,
            crop=inventory.crop,
            quantity_requested_kg=demand.quantity_requested_kg,
            quantity_to_sell_kg=quantity_to_sell,
            offered_price_per_kg=demand.offered_price_per_kg,
            estimated_revenue=round(quantity_to_sell * demand.offered_price_per_kg, 2),
            distance_km=demand.distance_km,
            pickup_in_hours=demand.pickup_in_hours,
            recommendation=recommendation,
            reason_labels=tuple(reasons),
        )

    def _reason_labels(
        self,
        inventory: InventoryStatus,
        demand: BuyerDemand,
        quantity_to_sell: float,
    ) -> list[str]:
        reasons = []
        if demand.distance_km <= 10:
            reasons.append("Nearby buyer")
        if demand.pickup_in_hours <= 24:
            reasons.append("Fast pickup")
        if quantity_to_sell >= inventory.quantity_kg * 0.8:
            reasons.append("Matches most available quantity")
        if demand.buyer_reliability >= 0.85:
            reasons.append("Reliable buyer")
        if inventory.shelf_life.urgency in {Urgency.HIGH, Urgency.URGENT, Urgency.EXPIRED_RISK}:
            reasons.append("Helps reduce spoilage risk")
        return reasons or ["Viable buyer option"]

    def _recommendation_text(self, inventory: InventoryStatus, demand: BuyerDemand) -> str:
        if inventory.shelf_life.urgency in {Urgency.URGENT, Urgency.EXPIRED_RISK} and demand.pickup_in_hours <= 24:
            return "Good urgent-sale option because pickup is soon."
        if demand.quantity_requested_kg >= inventory.quantity_kg:
            return "Good full-quantity match."
        if demand.distance_km <= 10:
            return "Good local option with lower transport risk."
        return "Useful option to compare before confirming the sale."
