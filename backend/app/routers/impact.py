"""Impact / Tracks dashboard router.

Returns the farm's stored impact metrics grouped by category so the frontend
can render the hackathon scoreboard (water saved, food rescued, CO2e avoided,
economic value recovered, yield gain). Data comes from `impact_metrics` rows
written by the impact layer after each LangGraph run.
"""

from fastapi import APIRouter, Depends, Query
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase

router = APIRouter(prefix="/impact", tags=["impact"])

METRIC_GROUPS = {
    "water_saved_liters": "precision_agriculture",
    "yield_gain_pct": "precision_agriculture",
    "fertilizer_reduction_pct": "precision_agriculture",
    "food_rescued_kg": "circular_supply_chain",
    "economic_value_recovered_inr": "circular_supply_chain",
    "co2e_avoided_kg": "circular_supply_chain",
}


@router.get("")
async def get_impact(farm_id: str = Query(...), current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("impact_metrics").select("*") \
        .eq("farm_id", farm_id) \
        .order("created_at", desc=True).limit(100).execute()
    rows = resp.data or []

    grouped = {"precision_agriculture": [], "circular_supply_chain": []}
    for row in rows:
        group = METRIC_GROUPS.get(row.get("metric_type"), "precision_agriculture")
        grouped[group].append(row)

    return {
        "farm_id": farm_id,
        "groups": grouped,
        "metrics": rows,
        "count": len(rows),
    }
