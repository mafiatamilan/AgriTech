from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase

router = APIRouter(prefix="/performance", tags=["performance"])


class CropPerformanceCreate(BaseModel):
    farm_id: str
    field_id: str | None = None
    crop: str
    season: str | None = None
    planted_date: str | None = None
    harvest_date: str | None = None
    yield_kg: float | None = None
    revenue: float | None = None
    cost: float | None = None
    profit: float | None = None
    weather_summary: dict = Field(default_factory=dict)
    notes: str | None = None


@router.post("/crop")
async def record_crop_performance(
    req: CropPerformanceCreate,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    farm = sb.table("farms").select("id").eq("id", req.farm_id).eq("farmer_id", current_farmer["id"]).execute()
    if not farm.data:
        raise HTTPException(status_code=404, detail="Farm not found")

    resp = sb.table("crop_performance_history").insert({
        "farm_id": req.farm_id,
        "field_id": req.field_id,
        "crop": req.crop,
        "season": req.season,
        "planted_date": req.planted_date,
        "harvest_date": req.harvest_date,
        "yield_kg": req.yield_kg,
        "revenue": req.revenue,
        "cost": req.cost,
        "profit": req.profit,
        # The database column is NOT NULL with a '{}' default. Explicitly
        # send an object because Supabase receives JSON null when the client
        # omits this optional field from the request model.
        "weather_summary": req.weather_summary or {},
        "notes": req.notes,
    }).execute()

    return resp.data[0] if resp.data else {"status": "created"}
