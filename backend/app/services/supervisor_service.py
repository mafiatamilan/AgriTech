"""Smart Farming Supervisor orchestration.

Runs the SmartFarmingSupervisorAgent and persists `smart_farming_reviews` +
an `agent_results` (smart_supervisor) row. Never blocks app flows when the
supervisor inputs are unavailable.
"""

from app.agents.runtime import agents
from app.services.weather_service import get_weather_snapshot


async def run_smart_supervisor(sb, farm_id: str) -> dict | None:
    smart = agents()["smart"]

    farm_resp = sb.table("farms").select("*").eq("id", farm_id).limit(1).execute()
    if not farm_resp.data:
        return None
    farm = farm_resp.data[0]

    field_resp = sb.table("field_area").select("*").eq("farm_id", farm_id).limit(1).execute()
    field = field_resp.data[0] if field_resp.data else None
    field_id = (field or {}).get("id")

    weather = await get_weather_snapshot(
        sb, farm_id, field_id=field_id, crop=(field or {}).get("crop_type"),
        farm_lat=farm.get("latitude"), farm_lon=farm.get("longitude"),
    )

    agri_context = None
    try:
        agri = agents()["agri"]
        m = agri.models
        context = m.CropFieldContext(
            farm_id=farm_id,
            field_id=field_id or farm_id,
            crop=(field or {}).get("crop_type") or "unknown",
            soil_type=_parse_enum(m.SoilType, (field or {}).get("soil_type") or farm.get("soil_type")) or m.SoilType.LOAMY,
            planting_date=_as_date((field or {}).get("planted_date")),
            growth_stage=_parse_enum(m.GrowthStage, (field or {}).get("growth_stage")),
        )
        ws = m.WeatherSnapshot(
            avg_temp_c=float(weather.get("avg_temp_c") or 0),
            max_temp_c=float(weather.get("max_temp_c") or 0),
            humidity_pct=float(weather.get("humidity_pct") or 0),
            rainfall_mm_today=float(weather.get("rainfall_mm_today") or 0),
            rainfall_forecast_mm_24h=float(weather.get("rainfall_forecast_mm_24h") or 0),
            sunlight_hours=float(weather.get("sunlight_hours") or 0),
            wind_speed_kmph=float(weather.get("wind_speed_kmph") or 0),
            condition=weather.get("condition") or "clear",
        )
        agri_context = (context, ws)
    except Exception:
        agri_context = None

    try:
        review = smart.SmartFarmingSupervisorAgent().full_review(
            agri_context=agri_context[0] if agri_context else None,
            agri_weather=agri_context[1] if agri_context else None,
            business_batches=[],
            business_weather_by_crop={},
            buyer_demands=[],
            crop_history=[],
        )
    except Exception:
        return None

    alerts = list(review.alerts)
    next_actions = list(review.next_actions)

    sb.table("smart_farming_reviews").insert({
        "farm_id": farm_id,
        "field_id": field_id,
        "alerts": alerts,
        "next_actions": next_actions,
    }).execute()

    sb.table("agent_results").insert({
        "farm_id": farm_id,
        "field_id": field_id,
        "agent_type": "smart_supervisor",
        "result_json": {"alerts": alerts, "next_actions": next_actions},
        "model_name": "SmartFarmingSupervisorAgent",
        "model_version": "1",
    }).execute()

    return {"alerts": alerts, "next_actions": next_actions}


def _as_date(value):
    if not value:
        return None
    from datetime import date
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except (ValueError, TypeError):
        return None


def _parse_enum(enum_cls, value):
    if not value:
        return None
    try:
        return enum_cls(value)
    except ValueError:
        return None