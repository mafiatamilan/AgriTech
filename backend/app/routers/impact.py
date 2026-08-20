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

KPI_MATRIX = [
    {
        "metric_type": "water_saved_liters",
        "label": "Water saved",
        "formula": "(default_watering_minutes - recommended_duration_minutes) * pump_flow_liters_per_min",
        "parameters": ["default_watering_minutes", "recommended_duration_minutes", "pump_flow_liters_per_min"],
        "source": "irrigation_agent",
    },
    {
        "metric_type": "food_rescued_kg",
        "label": "Food rescued",
        "formula": "sum(confirmed_or_matched_quantity_kg)",
        "parameters": ["rescue_matches.quantity_kg", "rescue_matches.status"],
        "source": "marketplace",
    },
    {
        "metric_type": "economic_value_recovered_inr",
        "label": "Value recovered",
        "formula": "sum(quantity_kg * offered_price_per_kg)",
        "parameters": ["rescue_matches.quantity_kg", "matched_buyer_info.offered_price"],
        "source": "marketplace",
    },
    {
        "metric_type": "co2e_avoided_kg",
        "label": "CO2e avoided",
        "formula": "food_rescued_kg * co2e_factor_kg_per_kg_food",
        "parameters": ["food_rescued_kg", "co2e_factor_kg_per_kg_food"],
        "source": "impact_service",
    },
    {
        "metric_type": "yield_gain_pct",
        "label": "Yield gain",
        "formula": "(expected_yield_kg - historical_baseline_yield_kg) / historical_baseline_yield_kg * 100",
        "parameters": ["expected_yield_kg", "crop_performance_history.yield_kg"],
        "source": "yield_agent",
    },
    {
        "metric_type": "vendor_confirmed_quantity_kg",
        "label": "Confirmed purchase volume",
        "formula": "sum(confirmed rescue_matches.quantity_kg for vendor)",
        "parameters": ["vendor_id", "rescue_matches.quantity_kg", "rescue_matches.status"],
        "source": "marketplace",
    },
]


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
        "kpi_matrix": KPI_MATRIX,
    }


@router.get("/kpi-matrix")
async def get_kpi_matrix(current_farmer: dict = Depends(get_current_farmer)):
    return {"items": KPI_MATRIX}
