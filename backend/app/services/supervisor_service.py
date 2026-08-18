"""Smart Farming Supervisor orchestration.

Runs the SmartFarmingSupervisorAgent with the real business-side data
(inventory, demand requests, crop history) that the other agents produced,
and persists `smart_farming_reviews` + an `agent_results` (smart_supervisor)
row. Never blocks app flows when inputs are unavailable.

The supervisor receives the actual LangGraph results when invoked from the
graph (`results=...`); standalone callers (scheduler) get the same inputs by
re-reading the database rows the agents wrote.
"""

from app.agents.runtime import agents
from app.services.weather_service import get_weather_snapshot


async def run_smart_supervisor(
    sb,
    farm_id: str,
    results: list | None = None,
    agent_run_id: str | None = None,
) -> dict | None:
    smart = agents()["smart"]
    biz = agents()["business"]
    agri = agents()["agri"]

    farm_resp = sb.table("farms").select("*").eq("id", farm_id).limit(1).execute()
    if not farm_resp.data:
        return None
    farm = farm_resp.data[0]

    field_resp = sb.table("field_area").select("*").eq("farm_id", farm_id).limit(1).execute()
    field = field_resp.data[0] if field_resp.data else None
    field_id = (field or {}).get("id")
    crop = (field or {}).get("crop_type")

    weather = await get_weather_snapshot(
        sb, farm_id, field_id=field_id, crop=crop,
        farm_lat=farm.get("latitude"), farm_lon=farm.get("longitude"),
    )

    agri_context = None
    try:
        m = agri.models
        context = m.CropFieldContext(
            farm_id=farm_id,
            field_id=field_id or farm_id,
            crop=crop or "unknown",
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

    # --- business-side inputs built from the real data the agents wrote ---
    business_batches = _load_inventory_batches(biz, sb, farm_id)
    business_weather_by_crop = _load_weather_by_crop(biz, weather, field_id, crop)
    buyer_demands = _load_buyer_demands(biz, sb)
    crop_history = _load_crop_history(biz, sb, farm_id)
    yield_signal = _load_yield_signal(agri, results)

    try:
        review = smart.SmartFarmingSupervisorAgent().full_review(
            agri_context=agri_context[0] if agri_context else None,
            agri_weather=agri_context[1] if agri_context else None,
            yield_prediction=yield_signal,
            business_batches=business_batches,
            business_weather_by_crop=business_weather_by_crop,
            buyer_demands=buyer_demands,
            crop_history=crop_history,
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
        "agent_run_id": agent_run_id,
    }).execute()

    sb.table("agent_results").insert({
        "farm_id": farm_id,
        "field_id": field_id,
        "agent_type": "smart_supervisor",
        "result_json": {"alerts": alerts, "next_actions": next_actions},
        "model_name": "SmartFarmingSupervisorAgent",
        "model_version": "1",
        "agent_run_id": agent_run_id,
    }).execute()

    return {
        "alerts": alerts,
        "next_actions": next_actions,
        "business_review": review.business_review is not None,
        "agri_review": review.agri_review is not None,
    }


def _load_inventory_batches(biz, sb, farm_id: str) -> list:
    """Convert the farm's real inventory rows into typed InventoryBatch."""
    rows = sb.table("inventory").select("*").eq("farm_id", farm_id).limit(20).execute()
    batches = []
    for inv in rows.data or []:
        try:
            storage = biz.models.StorageType(inv.get("storage_type")) if inv.get("storage_type") else biz.models.StorageType.AMBIENT
        except ValueError:
            storage = biz.models.StorageType.AMBIENT
        try:
            batches.append(biz.models.InventoryBatch(
                batch_id=inv["id"],
                crop=inv["crop_name"],
                quantity_kg=float(inv.get("quantity") or 0),
                harvest_date=_as_date(inv.get("harvested_date")) or _today(),
                storage_type=storage,
                quality_grade=inv.get("quality_grade") or "A",
                farm_id=farm_id,
            ))
        except Exception:
            continue
    return batches


def _load_weather_by_crop(biz, weather: dict, field_id, crop) -> dict:
    bw = biz.models.WeatherSnapshot(
        avg_temp_c=float(weather.get("avg_temp_c") or 0),
        max_temp_c=float(weather.get("max_temp_c") or 0),
        humidity_pct=float(weather.get("humidity_pct") or 0),
        rainfall_mm=float(weather.get("rainfall_mm_today") or 0),
        condition=weather.get("condition") or "clear",
    )
    result = {"default": bw}
    if crop:
        result[crop] = bw
    return result


def _load_buyer_demands(biz, sb) -> list:
    """Open vendor requests become typed BuyerDemands for the supervisor."""
    rows = sb.table("vendor_requests").select("*, vendors(business_name, reliability_score)") \
        .eq("status", "open").limit(50).execute()
    demands = []
    for vr in rows.data or []:
        vendor = (vr.get("vendors") or {})
        try:
            demands.append(biz.models.BuyerDemand(
                buyer_id=vr.get("vendor_id"),
                buyer_name=vendor.get("business_name") or "Vendor",
                crop=vr["crop_name"],
                quantity_requested_kg=float(vr.get("quantity_needed") or 1),
                offered_price_per_kg=float(vr.get("expected_price") or 0),
                distance_km=0.0,
                pickup_in_hours=24.0,
                buyer_reliability=float(vendor.get("reliability_score") or 0.8),
            ))
        except Exception:
            continue
    return demands


def _load_crop_history(biz, sb, farm_id: str) -> list:
    rows = sb.table("crop_performance_history").select("*").eq("farm_id", farm_id).limit(50).execute()
    history = []
    for h in rows.data or []:
        sales_kg = float(h.get("yield_kg") or 0)
        price = float(h.get("revenue") or 0) / sales_kg if sales_kg else 0
        cost = float(h.get("cost") or 0) / sales_kg if sales_kg else 0
        try:
            history.append(biz.models.CropPerformance(
                crop=h["crop"],
                sales_kg=sales_kg,
                avg_price_per_kg=price,
                production_cost_per_kg=cost,
                unsold_or_waste_kg=float(h.get("unsold_or_waste_kg") or 0),
            ))
        except Exception:
            continue
    return history


def _load_yield_signal(agri, results: list | None):
    """Pull the latest successful yield output into a typed signal."""
    if results:
        for item in results:
            if item.get("agent") == "yield" and item.get("status") == "success":
                out = item.get("output") or {}
                m = agri.models
                return m.YieldPredictionSignal(
                    crop=out.get("crop_type") or "unknown",
                    expected_yield_kg=out.get("expected_yield_kg"),
                    confidence_level=_parse_enum(m.ConfidenceLevel, out.get("confidence_level")),
                    risk_factors=tuple(out.get("risk_factors") or []),
                )
    return None


def _as_date(value):
    from datetime import date
    if not value:
        return None
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except (ValueError, TypeError):
        return None


def _today():
    from datetime import date
    return date.today()


def _parse_enum(enum_cls, value):
    if not value:
        return None
    try:
        return enum_cls(value)
    except ValueError:
        return None
