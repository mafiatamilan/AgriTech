"""Next-season crop planning orchestration.

Runs the CropPlanningAdvisor over `crop_performance_history` and persists
`crop_plan_recommendations` + an `agent_results` (next_season) row.
"""

from app.agents.runtime import agents


async def run_next_season(sb, farm_id: str, agent_run_id: str | None = None) -> dict | None:
    biz = agents()["business"]

    history_resp = sb.table("crop_performance_history").select("*") \
        .eq("farm_id", farm_id).execute()
    history_rows = history_resp.data or []
    if not history_rows:
        return None

    history = []
    for h in history_rows:
        sales_kg = float(h.get("yield_kg") or 0)
        price = float(h.get("revenue") or 0) / sales_kg if sales_kg else 0
        cost = float(h.get("cost") or 0) / sales_kg if sales_kg else 0
        history.append(biz.models.CropPerformance(
            crop=h["crop"],
            sales_kg=sales_kg,
            avg_price_per_kg=price,
            production_cost_per_kg=cost,
            unsold_or_waste_kg=0.0,
        ))

    try:
        result = biz.CropPlanningAdvisor().recommend_crops(history)
    except Exception:
        return None
    if not result.recommendations:
        return None

    sb.table("crop_plan_recommendations").delete().eq("farm_id", farm_id).execute()
    for rec in result.recommendations:
        sb.table("crop_plan_recommendations").insert({
            "farm_id": farm_id,
            "rank": rec.rank,
            "crop": rec.crop,
            "expected_profit_per_kg": rec.expected_profit_per_kg,
            "demand_outlook": rec.demand_outlook,
            "waste_risk": rec.waste_risk,
            "planning_risk": rec.planning_risk,
            "recommendation": rec.recommendation,
            "reason_labels": list(rec.reason_labels),
            "suggested_crop_mix_pct": rec.suggested_crop_mix_pct,
        }).execute()

    sb.table("agent_results").insert({
        "farm_id": farm_id,
        "agent_type": "next_season",
        "result_json": {
            "recommended_crops": [
                {"crop": rec.crop, "reason": rec.recommendation, "confidence": None}
                for rec in result.recommendations
            ]
        },
        "model_name": "CropPlanningAdvisor",
        "model_version": "1",
        "agent_run_id": agent_run_id,
    }).execute()

    return {"recommended_crops": [rec.crop for rec in result.recommendations]}