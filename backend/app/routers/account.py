from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase

router = APIRouter(prefix="/account", tags=["account"])


class AccountUpdate(BaseModel):
    name: str | None = None
    phone: str | None = None
    email: str | None = None


@router.get("")
async def get_account(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("farmers").select("*").eq("id", current_farmer["id"]).execute()
    if not resp.data:
        return {}

    metrics = sb.table("impact_metrics").select("*") \
        .eq("farmer_id", current_farmer["id"]).order("created_at", desc=True).limit(10).execute()

    return {
        "profile": resp.data[0],
        "impact_metrics": metrics.data,
    }


@router.patch("")
async def update_account(req: AccountUpdate, current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    update_data = req.model_dump(exclude_unset=True, exclude_none=True)
    if update_data:
        sb.table("farmers").update(update_data).eq("id", current_farmer["id"]).execute()
    return {"status": "updated"}


@router.get("/water-saved")
async def get_water_saved(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("farmer_water_saved_totals").select("total_water_saved_liters") \
        .eq("farmer_id", current_farmer["id"]).execute()
    if resp.data:
        return {"total_water_saved_liters": resp.data[0]["total_water_saved_liters"]}

    fallback = sb.table("impact_metrics").select("value") \
        .eq("farmer_id", current_farmer["id"]) \
        .eq("metric_type", "water_saved_liters").execute()
    total = sum(float(row.get("value") or 0) for row in fallback.data or [])
    return {"total_water_saved_liters": round(total, 2)}
