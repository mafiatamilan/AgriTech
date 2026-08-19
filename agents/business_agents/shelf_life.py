from __future__ import annotations

from datetime import date, timedelta

from .crop_profiles import get_crop_profile
from .models import CropProfile, InventoryBatch, ShelfLifeEstimate, StorageType, Urgency, WeatherSnapshot


STORAGE_MULTIPLIERS: dict[StorageType, float] = {
    StorageType.AMBIENT: 1.0,
    StorageType.SHADED: 1.15,
    StorageType.EVAPORATIVE_COOLER: 1.35,
    StorageType.REFRIGERATED: 1.8,
}

CONDITION_RISK: dict[str, float] = {
    "clear": 0.0,
    "cloudy": 0.03,
    "humid": 0.08,
    "rain": 0.12,
    "storm": 0.18,
    "heatwave": 0.22,
}


class ShelfLifeEngine:
    """Heuristic shelf-life estimator used by the Inventory Agent.

    The backend can replace the crop profiles or weather source later without changing
    the agent contract.
    """

    def __init__(self, crop_profiles: dict[str, CropProfile] | None = None) -> None:
        self.crop_profiles = crop_profiles

    def estimate(
        self,
        batch: InventoryBatch,
        weather: WeatherSnapshot,
        today: date | None = None,
    ) -> ShelfLifeEstimate:
        today = today or date.today()
        profile = get_crop_profile(batch.crop, self.crop_profiles)
        factors: list[str] = []

        storage_multiplier = STORAGE_MULTIPLIERS.get(batch.storage_type, 1.0)
        if batch.storage_type != StorageType.AMBIENT:
            factors.append(f"{batch.storage_type.value.replace('_', ' ')} storage extends usable life")

        temp_stress = self._temperature_stress(profile, weather, factors)
        humidity_stress = self._humidity_stress(profile, weather, factors)
        rain_stress = self._rain_stress(profile, weather, factors)
        condition_stress = CONDITION_RISK.get(weather.condition.strip().lower(), 0.05)
        if condition_stress > 0.1:
            factors.append(f"{weather.condition} weather increases spoilage risk")

        total_stress = 1.0 + temp_stress + humidity_stress + rain_stress + condition_stress
        estimated_life = max(0.75, profile.base_shelf_life_days * storage_multiplier / total_stress)

        days_since_harvest = max(0, (today - batch.harvest_date).days)
        remaining = estimated_life - days_since_harvest
        sell_by = batch.harvest_date + timedelta(days=max(0, int(estimated_life)))
        urgency = self._urgency(remaining, estimated_life)

        if not factors:
            factors.append("weather is close to the crop's preferred storage range")

        return ShelfLifeEstimate(
            crop=profile.crop,
            plant_type=profile.plant_type,
            estimated_shelf_life_days=round(estimated_life, 1),
            remaining_shelf_life_days=round(remaining, 1),
            sell_by_date=sell_by,
            urgency=urgency,
            spoilage_risk=self._spoilage_risk(urgency),
            recommendation="",
            factors=tuple(factors),
        )

    def _temperature_stress(
        self,
        profile: CropProfile,
        weather: WeatherSnapshot,
        factors: list[str],
    ) -> float:
        avg_excess = max(0.0, weather.avg_temp_c - profile.ideal_temp_max_c)
        max_excess = max(0.0, weather.max_temp_c - profile.ideal_temp_max_c)
        cold_excess = max(0.0, profile.ideal_temp_min_c - weather.avg_temp_c)
        stress = ((avg_excess * 0.055) + (max_excess * 0.025) + (cold_excess * 0.03)) * profile.temp_sensitivity
        if avg_excess >= 4 or max_excess >= 7:
            factors.append("temperature is above the safe range for this crop")
        elif cold_excess >= 4:
            factors.append("temperature is below the preferred range for this crop")
        return min(stress, 1.6)

    def _humidity_stress(
        self,
        profile: CropProfile,
        weather: WeatherSnapshot,
        factors: list[str],
    ) -> float:
        high_excess = max(0.0, weather.humidity_pct - profile.ideal_humidity_max_pct)
        low_excess = max(0.0, profile.ideal_humidity_min_pct - weather.humidity_pct)
        stress = ((high_excess * 0.012) + (low_excess * 0.008)) * profile.humidity_sensitivity
        if high_excess >= 8:
            factors.append("high humidity increases fungal and spoilage risk")
        elif low_excess >= 12:
            factors.append("low humidity can reduce freshness and weight")
        return min(stress, 0.8)

    def _rain_stress(
        self,
        profile: CropProfile,
        weather: WeatherSnapshot,
        factors: list[str],
    ) -> float:
        if weather.rainfall_mm <= 0:
            return 0.0
        stress = min(0.7, (weather.rainfall_mm / 40.0) * profile.rain_sensitivity)
        if weather.rainfall_mm >= 10:
            factors.append("rainfall raises handling and transport spoilage risk")
        return stress

    def _urgency(self, remaining_days: float, estimated_life_days: float) -> Urgency:
        if remaining_days <= 0:
            return Urgency.EXPIRED_RISK
        if remaining_days <= 1:
            return Urgency.URGENT
        if remaining_days <= 2.5:
            return Urgency.HIGH
        if remaining_days <= min(5, estimated_life_days * 0.45):
            return Urgency.MEDIUM
        return Urgency.LOW

    def _spoilage_risk(self, urgency: Urgency) -> str:
        return {
            Urgency.LOW: "low",
            Urgency.MEDIUM: "moderate",
            Urgency.HIGH: "high",
            Urgency.URGENT: "very high",
            Urgency.EXPIRED_RISK: "critical",
        }[urgency]

    def _recommendation(self, urgency: Urgency) -> str:
        return {
            Urgency.LOW: "Inventory is stable. Normal selling is fine.",
            Urgency.MEDIUM: "Start prioritizing active buyers and monitor weather.",
            Urgency.HIGH: "Prioritize nearby buyers and faster pickup windows.",
            Urgency.URGENT: "Sell or dispatch within 24 hours to reduce waste.",
            Urgency.EXPIRED_RISK: "Check quality before sale and avoid long-distance transport.",
        }[urgency]
