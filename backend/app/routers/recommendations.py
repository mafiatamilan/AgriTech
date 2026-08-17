from fastapi import APIRouter, Depends, Query
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase

router = APIRouter(prefix="/recommendations", tags=["recommendations"])


@router.get("")
async def get_recommendations(
    farm_id: str = Query(...),
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()

    agent_results = sb.table("agent_results").select("*") \
        .eq("farm_id", farm_id).order("created_at", desc=True).limit(10).execute()

    yield_forecasts = sb.table("yield_forecasts").select("*") \
        .eq("farm_id", farm_id).order("created_at", desc=True).limit(5).execute()

    crop_plans = sb.table("crop_plan_recommendations").select("*") \
        .eq("farm_id", farm_id).order("rank", desc=False).execute()

    latest_health = None
    latest_yield = None
    latest_next_season = None

    for r in agent_results.data:
        if r["agent_type"] == "health" and latest_health is None:
            latest_health = r
        elif r["agent_type"] == "yield" and latest_yield is None:
            latest_yield = r
        elif r["agent_type"] == "next_season" and latest_next_season is None:
            latest_next_season = r

    return {
        "health_analysis": latest_health,
        "yield_analysis": latest_yield,
        "next_season_recommendations": latest_next_season,
        "yield_forecasts": yield_forecasts.data,
        "crop_plan_recommendations": crop_plans.data,
    }
