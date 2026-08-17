from __future__ import annotations

from datetime import date
from uuid import uuid4

from .growth_stage import GrowthStageEstimator
from .models import (
    CropFieldContext,
    GrowthStage,
    GrowthStageEstimate,
    IrrigationDecision,
    IrrigationUrgency,
    MqttIrrigationCommand,
    SoilType,
    WeatherSnapshot,
)


CROP_DAILY_WATER_MM: dict[str, float] = {
    "tomato": 5.0,
    "okra": 4.8,
    "spinach": 3.4,
    "onion": 4.0,
    "potato": 4.6,
    "maize": 5.5,
}

SOIL_TYPE_MULTIPLIER: dict[SoilType, float] = {
    SoilType.SANDY: 1.25,
    SoilType.LOAMY: 1.0,
    SoilType.SILTY: 0.95,
    SoilType.CLAY: 0.8,
    SoilType.PEATY: 0.75,
}

GROWTH_STAGE_MULTIPLIER: dict[GrowthStage, float] = {
    GrowthStage.GERMINATION: 0.65,
    GrowthStage.SEEDLING: 0.75,
    GrowthStage.VEGETATIVE: 1.0,
    GrowthStage.FLOWERING: 1.25,
    GrowthStage.FRUITING: 1.3,
    GrowthStage.MATURITY: 0.85,
    GrowthStage.UNKNOWN: 1.0,
}


class SoilTypeIrrigationAgent:
    """Irrigation decision logic without soil sensors or root-zone inputs."""

    def __init__(
        self,
        growth_stage_estimator: GrowthStageEstimator | None = None,
        pump_delivery_mm_per_minute: float = 0.35,
    ) -> None:
        self.growth_stage_estimator = growth_stage_estimator or GrowthStageEstimator()
        self.pump_delivery_mm_per_minute = pump_delivery_mm_per_minute

    def decide(
        self,
        context: CropFieldContext,
        weather: WeatherSnapshot,
        today: date | None = None,
    ) -> IrrigationDecision:
        today = today or date.today()
        growth_stage = self.growth_stage_estimator.estimate(context, today)
        reasons: list[str] = []

        base_need = CROP_DAILY_WATER_MM.get(context.crop.strip().lower(), 4.5)
        stage_multiplier = GROWTH_STAGE_MULTIPLIER[growth_stage.stage]
        soil_multiplier = SOIL_TYPE_MULTIPLIER[context.soil_type]
        weather_multiplier = self._weather_multiplier(weather, reasons)
        last_irrigation_multiplier = self._last_irrigation_multiplier(context.last_irrigation_date, today, reasons)
        rain_reduction = self._rain_reduction(weather, reasons)

        water_need = base_need * stage_multiplier * soil_multiplier * weather_multiplier * last_irrigation_multiplier
        adjusted_need = max(0.0, water_need - rain_reduction)
        urgency = self._urgency(adjusted_need, weather)
        irrigation_needed = urgency != IrrigationUrgency.NONE
        duration = self._duration_minutes(adjusted_need) if irrigation_needed else 0

        if context.soil_type == SoilType.SANDY:
            reasons.append("Sandy soil dries faster")
        elif context.soil_type in {SoilType.CLAY, SoilType.PEATY}:
            reasons.append("Soil type retains water longer")

        if growth_stage.stage in {GrowthStage.FLOWERING, GrowthStage.FRUITING}:
            reasons.append("Growth stage has higher water demand")

        mqtt_command = None
        if irrigation_needed and context.auto_irrigation_enabled:
            mqtt_command = self._build_mqtt_command(context, duration, adjusted_need, reasons)

        return IrrigationDecision(
            field_id=context.field_id,
            crop=context.crop,
            growth_stage=growth_stage,
            irrigation_needed=irrigation_needed,
            urgency=urgency,
            recommended_duration_minutes=duration,
            estimated_water_need_mm=round(adjusted_need, 2),
            recommendation=self._recommendation(irrigation_needed, context.auto_irrigation_enabled, duration),
            reason_labels=tuple(dict.fromkeys(reasons)),
            mqtt_command=mqtt_command,
        )

    def _weather_multiplier(self, weather: WeatherSnapshot, reasons: list[str]) -> float:
        multiplier = 1.0
        if weather.avg_temp_c > 30:
            multiplier += min(0.35, (weather.avg_temp_c - 30) * 0.045)
            reasons.append("High temperature increases water need")
        if weather.max_temp_c > 36:
            multiplier += 0.12
            reasons.append("Peak heat increases evaporation")
        if weather.humidity_pct < 45:
            multiplier += 0.12
            reasons.append("Low humidity dries field faster")
        if weather.sunlight_hours > 8:
            multiplier += 0.08
            reasons.append("Long sunlight exposure increases evaporation")
        if weather.wind_speed_kmph > 18:
            multiplier += 0.08
            reasons.append("Wind increases field drying")
        if weather.condition.lower() in {"storm", "heavy rain"}:
            multiplier -= 0.2
        return max(0.55, multiplier)

    def _last_irrigation_multiplier(
        self,
        last_irrigation_date: date | None,
        today: date,
        reasons: list[str],
    ) -> float:
        if not last_irrigation_date:
            reasons.append("Last irrigation date is unavailable")
            return 1.1

        days_since = max(0, (today - last_irrigation_date).days)
        if days_since >= 3:
            reasons.append("Several days since last irrigation")
            return 1.25
        if days_since == 0:
            reasons.append("Field was irrigated today")
            return 0.55
        if days_since == 1:
            return 0.85
        return 1.0

    def _rain_reduction(self, weather: WeatherSnapshot, reasons: list[str]) -> float:
        rain_total = weather.rainfall_mm_today + weather.rainfall_forecast_mm_24h
        if rain_total >= 8:
            reasons.append("Rainfall reduces irrigation need")
        return min(8.0, rain_total * 0.7)

    def _urgency(self, water_need_mm: float, weather: WeatherSnapshot) -> IrrigationUrgency:
        if water_need_mm < 1.2:
            return IrrigationUrgency.NONE
        if water_need_mm < 3:
            return IrrigationUrgency.LOW
        if water_need_mm < 5.5:
            return IrrigationUrgency.MEDIUM
        return IrrigationUrgency.HIGH

    def _duration_minutes(self, water_need_mm: float) -> int:
        if self.pump_delivery_mm_per_minute <= 0:
            raise ValueError("pump_delivery_mm_per_minute must be greater than 0.")
        return max(1, round(water_need_mm / self.pump_delivery_mm_per_minute))

    def _build_mqtt_command(
        self,
        context: CropFieldContext,
        duration_minutes: int,
        water_need_mm: float,
        reasons: list[str],
    ) -> MqttIrrigationCommand:
        topic = f"farms/{context.farm_id}/fields/{context.field_id}/irrigation/command"
        payload = {
            "commandId": str(uuid4()),
            "action": "START",
            "fieldId": context.field_id,
            "crop": context.crop,
            "durationMinutes": duration_minutes,
            "estimatedWaterNeedMm": round(water_need_mm, 2),
            "source": "agri_supervisor_agent",
            "autoMode": True,
            "reasonLabels": tuple(dict.fromkeys(reasons)),
        }
        return MqttIrrigationCommand(topic=topic, payload=payload)

    def _recommendation(self, irrigation_needed: bool, auto_enabled: bool, duration: int) -> str:
        if not irrigation_needed:
            return "Irrigation is not needed now."
        if auto_enabled:
            return f"Auto irrigation command prepared for {duration} minutes."
        return f"Irrigation is recommended for {duration} minutes. Farmer approval is required in manual mode."


SoilMoistureIrrigationAgent = SoilTypeIrrigationAgent
