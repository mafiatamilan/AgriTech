from datetime import date
from fastapi import APIRouter, HTTPException, Depends, Request
from pydantic import BaseModel, Field, ValidationError
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.services.inventory_service import record_inventory

router = APIRouter(prefix="/inventory", tags=["inventory"])


class InventoryCreate(BaseModel):
    farm_id: str
    crop_name: str
    quantity: float
    harvested_date: str | None = None
    field_id: str | None = None
    storage_type: str | None = None
    quality_grade: str | None = None


@router.get("")
async def list_inventory(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    farms = sb.table("farms").select("id").eq("farmer_id", current_farmer["id"]).execute()
    farm_ids = [f["id"] for f in farms.data or []]
    if not farm_ids:
        return []

    rows = sb.table("inventory").select("*").in_("farm_id", farm_ids) \
        .order("created_at", desc=True).execute()

    inventory = rows.data or []
    if not inventory:
        return []

    ids = [i["id"] for i in inventory]
    statuses = sb.table("inventory_statuses").select("*") \
        .in_("inventory_id", ids).order("created_at", desc=True).execute()
    by_inv: dict[str, dict] = {}
    for s in statuses.data or []:
        if s["inventory_id"] not in by_inv:
            by_inv[s["inventory_id"]] = s

    for item in inventory:
        item["status_info"] = by_inv.get(item["id"])
    return inventory


@router.post("")
async def add_inventory(
    request: Request,
    current_farmer: dict = Depends(get_current_farmer),
):
    """Create inventory from either JSON or multipart form data.

    The Flutter client sends JSON, while older clients used multipart form
    data. Supporting both avoids a client-version-dependent 422 response.
    """
    content_type = request.headers.get("content-type", "").lower()
    try:
        raw = await request.form() if content_type.startswith("multipart/") else await request.json()
        req = InventoryCreate.model_validate(dict(raw))
    except (ValidationError, ValueError, TypeError) as exc:
        detail = exc.errors() if isinstance(exc, ValidationError) else "Invalid inventory payload"
        raise HTTPException(status_code=422, detail=detail) from exc

    sb = get_supabase()
    farm = sb.table("farms").select("id").eq("id", req.farm_id).eq("farmer_id", current_farmer["id"]).execute()
    if not farm.data:
        raise HTTPException(status_code=404, detail="Farm not found")

    harvested = req.harvested_date or date.today().isoformat()
    return await record_inventory(
        sb, current_farmer["id"], req.farm_id, req.crop_name, req.quantity,
        harvested_date=harvested, field_id=req.field_id,
        storage_type=req.storage_type, quality_grade=req.quality_grade,
    )
