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


class WaterIrrigationAgent:
    """Irrigation decision logic without soil sensors or root-zone inputs.

    Duration is derived from the farmer's configured pump flow rate
    (L/min) and field area (m²):

        water_volume_liters = water_depth_mm * field_area_m2   (1 mm over 1 m² = 1 L)
        duration_minutes    = water_volume_liters / pump_flow_lpm

    Legacy records without those values fall back to a fixed mm/min
    delivery estimate (LEGACY_PUMP_DELIVERY_MM_PER_MIN) and the result is
    clearly marked as estimated so it is never mistaken for the real pump.
    """

    # ponytail: legacy-only fallback, marked as estimated in every result
    LEGACY_PUMP_DELIVERY_MM_PER_MIN = 0.35

    def __init__(
        self,
        growth_stage_estimator: GrowthStageEstimator | None = None,
        pump_delivery_mm_per_minute: float = LEGACY_PUMP_DELIVERY_MM_PER_MIN,
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
        adjusted_need = round(max(0.0, water_need - rain_reduction), 2)
        urgency = self._urgency(adjusted_need, weather)
        irrigation_needed = urgency != IrrigationUrgency.NONE
        duration, volume, pump_flow, pump_estimated = self._duration_and_volume(
            context, adjusted_need, reasons
        )

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
            recommended_duration_minutes=duration if irrigation_needed else 0,
            estimated_water_need_mm=adjusted_need,
            recommendation=self._recommendation(irrigation_needed, context.auto_irrigation_enabled, duration, volume, pump_flow, pump_estimated),
            reason_labels=tuple(dict.fromkeys(reasons)),
            mqtt_command=mqtt_command,
            estimated_water_volume_liters=round(volume, 1) if irrigation_needed and volume is not None else None,
            field_area_m2=context.field_area_m2,
            pump_flow_lpm=pump_flow,
            pump_flow_estimated=pump_estimated,
        )

    def _duration_and_volume(
        self,
        context: CropFieldContext,
        adjusted_need_mm: float,
        reasons: list[str],
    ) -> tuple[int, float | None, float | None, bool]:
        """Convert water depth to a runtime using area + configured pump flow.

        Returns (duration_minutes, water_volume_liters, pump_flow_lpm,
        pump_flow_estimated). Falls back to the fixed mm/min estimate for
        legacy records, and says so in the reasons.
        """
        area = context.field_area_m2
        pump = context.pump_flow_lpm

        if area is not None and pump is not None and area > 0 and pump > 0:
            volume = adjusted_need_mm * area  # 1 mm over 1 m² = 1 L
            duration = max(1, round(volume / pump))
            reasons.append(f"Using configured pump flow {pump:g} L/min and {area:g} m² field area")
            return duration, volume, pump, False

        duration = max(1, round(adjusted_need_mm / self.pump_delivery_mm_per_minute))
        missing = []
        if area is None or area <= 0:
            missing.append("field area")
        if pump is None or pump <= 0:
            missing.append("pump flow")
        reasons.append(
            f"Using fallback pump estimate ({self.pump_delivery_mm_per_minute:g} mm/min) — configure {', '.join(missing)} for accurate watering"
        )
        return duration, None, None, True

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
            "estimatedWaterVolumeLiters": round(water_need_mm * context.field_area_m2, 1)
            if context.field_area_m2 else None,
            "source": "agri_supervisor_agent",
            "autoMode": True,
            "reasonLabels": tuple(dict.fromkeys(reasons)),
        }
        return MqttIrrigationCommand(topic=topic, payload=payload)

    def _recommendation(
        self,
        irrigation_needed: bool,
        auto_enabled: bool,
        duration: int,
        volume: float | None = None,
        pump_flow: float | None = None,
        pump_estimated: bool = False,
    ) -> str:
        if not irrigation_needed:
            return "Irrigation is not needed now."
        detail = f" for {duration} minutes"
        if volume is not None and pump_flow is not None:
            detail += f", estimated water {volume:.0f} L at {pump_flow:g} L/min"
        if pump_estimated:
            detail += " (pump flow estimated — configure it for accuracy)"
        if auto_enabled:
            return f"Auto irrigation command prepared{detail}."
        return f"Irrigation is recommended{detail}. Farmer approval is required in manual mode."


SoilTypeIrrigationAgent = WaterIrrigationAgent
SoilMoistureIrrigationAgent = WaterIrrigationAgent
