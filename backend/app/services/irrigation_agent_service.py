"""Irrigation agent orchestration.

Collects farm/field/crop/weather/moisture/device context, runs the
WaterIrrigationAgent, persists the decision in `irrigation_decisions` +
`agent_results`, and dispatches a hardware command when watering is required.
"""

from datetime import date, datetime

from app.agents.runtime import agents
from app.services.hardware_service import queue_hardware_command
from app.services.notification_service import create_notification
from app.services.weather_service import get_weather_snapshot

URGENCY_TO_DECISION = {
    "none": "skip",
    "low": "delay",
    "medium": "monitor",
    "high": "water_now",
}


async def run_irrigation_decision(
    sb, farm_id: str, farmer_id: str | None = None, agent_run_id: str | None = None
) -> dict | None:
    agri = agents()["agri"]

    farm_resp = sb.table("farms").select("*").eq("id", farm_id).limit(1).execute()
    if not farm_resp.data:
        return None
    farm = farm_resp.data[0]
    farmer_id = farmer_id or farm.get("farmer_id")

    field_resp = sb.table("field_area").select("*").eq("farm_id", farm_id).limit(1).execute()
    field = field_resp.data[0] if field_resp.data else None
    field_id = (field or {}).get("id")

    crop = (field or {}).get("crop_type")
    soil = (field or {}).get("soil_type") or farm.get("soil_type")
    growth_stage = (field or {}).get("growth_stage")
    planting_date = (field or {}).get("planted_date")
    area_size = (field or {}).get("area_size")
    pump_flow_lpm = (field or {}).get("pump_flow_lpm")

    weather = await get_weather_snapshot(
        sb, farm_id, field_id=field_id, crop=crop,
        farm_lat=farm.get("latitude"), farm_lon=farm.get("longitude"),
    )

    moisture_pct = None
    reading = sb.table("sensor_readings").select("moisture_pct") \
        .eq("farm_id", farm_id).order("recorded_at", desc=True).limit(1).execute()
    if reading.data and reading.data[0].get("moisture_pct") is not None:
        moisture_pct = reading.data[0]["moisture_pct"]

    last_irrigation_date = None
    last_evt = sb.table("irrigation_events").select("scheduled_time") \
        .eq("farm_id", farm_id).in_("status", ["completed", "stopped"]) \
        .order("scheduled_time", desc=True).limit(1).execute()
    if last_evt.data and last_evt.data[0].get("scheduled_time"):
        last_irrigation_date = _as_date(last_evt.data[0]["scheduled_time"])

    device_resp = sb.table("farm_devices").select("device_uid, motor_relay_state") \
        .eq("farm_id", farm_id).limit(1).execute()
    device = device_resp.data[0] if device_resp.data else None

    m = agri.models
    context = m.CropFieldContext(
        farm_id=farm_id,
        field_id=field_id or farm_id,
        crop=crop or "unknown",
        soil_type=_parse_enum(m.SoilType, soil) or m.SoilType.LOAMY,
        planting_date=_as_date(planting_date),
        growth_stage=_parse_enum(m.GrowthStage, growth_stage),
        last_irrigation_date=last_irrigation_date,
        auto_irrigation_enabled=bool(device),
        field_area_m2=_as_float(area_size),
        pump_flow_lpm=_as_float(pump_flow_lpm),
    )
    weather_obj = m.WeatherSnapshot(
        avg_temp_c=float(weather.get("avg_temp_c") or 0),
        max_temp_c=float(weather.get("max_temp_c") or 0),
        humidity_pct=float(weather.get("humidity_pct") or 0),
        rainfall_mm_today=float(weather.get("rainfall_mm_today") or 0),
        rainfall_forecast_mm_24h=float(weather.get("rainfall_forecast_mm_24h") or 0),
        sunlight_hours=float(weather.get("sunlight_hours") or 0),
        wind_speed_kmph=float(weather.get("wind_speed_kmph") or 0),
        condition=weather.get("condition") or "clear",
    )

    decision = agri.WaterIrrigationAgent().decide(context, weather_obj)
    decision_label = URGENCY_TO_DECISION.get(decision.urgency.value, "monitor")
    reasoning = decision.recommendation or " ".join(decision.reason_labels)

    agent_result = {
        "decision": decision_label,
        "recommended_duration_minutes": decision.recommended_duration_minutes,
        "reasoning": reasoning,
        "confidence": None,
        "reason_labels": list(decision.reason_labels),
        "estimated_water_need_mm": decision.estimated_water_need_mm,
        "estimated_water_volume_liters": decision.estimated_water_volume_liters,
        "field_area_m2": decision.field_area_m2,
        "pump_flow_lpm": decision.pump_flow_lpm,
        "pump_flow_estimated": decision.pump_flow_estimated,
    }

    row = {
        "farm_id": farm_id,
        "field_id": field_id,
        "weather_snapshot_id": weather.get("id"),
        "soil_type": soil,
        "crop": crop,
        "growth_stage": decision.growth_stage.stage.value if decision.growth_stage else None,
        "moisture_pct": moisture_pct,
        "rainfall_forecast_mm_24h": weather.get("rainfall_forecast_mm_24h"),
        "decision": decision_label,
        "recommended_duration_minutes": decision.recommended_duration_minutes,
        "recommended_start_at": datetime.utcnow().isoformat() if decision_label == "water_now" else None,
        "reasoning": reasoning,
        "confidence": None,
        "agent_result": agent_result,
        "agent_run_id": agent_run_id,
    }
    resp = sb.table("irrigation_decisions").insert(row).execute()
    decision_id = resp.data[0]["id"] if resp.data else None

    sb.table("agent_results").insert({
        "farm_id": farm_id,
        "field_id": field_id,
        "agent_type": "irrigation",
        "result_json": agent_result,
        "model_name": "WaterIrrigationAgent",
        "model_version": "1",
        "agent_run_id": agent_run_id,
    }).execute()

    if decision_label == "water_now":
        event_id = _create_irrigation_event(sb, farm_id, decision.recommended_duration_minutes)
        if device:
            queue_hardware_command(sb, farm_id, "on", event_id, agent_run_id=agent_run_id)
        if farmer_id:
            await create_notification(
                sb, farmer_id, "watering",
                "Irrigation Recommended",
                f"Water now for {decision.recommended_duration_minutes} minutes.",
                decision_id,
            )

    return agent_result


def _create_irrigation_event(sb, farm_id: str, duration_minutes: int) -> str | None:
    now = datetime.utcnow().isoformat()
    resp = sb.table("irrigation_events").insert({
        "farm_id": farm_id,
        "scheduled_time": now,
        "started_at": now,
        "status": "running",
    }).execute()
    return resp.data[0]["id"] if resp.data else None


def _as_date(value):
    if not value:
        return None
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except (ValueError, TypeError):
        return None


def _as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _parse_enum(enum_cls, value):
    if not value:
        return None
    try:
        return enum_cls(value)
    except ValueError:
        return None