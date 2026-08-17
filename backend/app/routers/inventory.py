from datetime import date
from fastapi import APIRouter, HTTPException, Depends, Form
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.services.inventory_service import record_inventory

router = APIRouter(prefix="/inventory", tags=["inventory"])


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
    farm_id: str = Form(...),
    crop_name: str = Form(...),
    quantity: float = Form(...),
    harvested_date: str = Form(None),
    field_id: str = Form(None),
    storage_type: str = Form(None),
    quality_grade: str = Form(None),
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    farm = sb.table("farms").select("id").eq("id", farm_id).eq("farmer_id", current_farmer["id"]).execute()
    if not farm.data:
        raise HTTPException(status_code=404, detail="Farm not found")

    harvested = harvested_date or date.today().isoformat()
    return await record_inventory(
        sb, current_farmer["id"], farm_id, crop_name, quantity,
        harvested_date=harvested, field_id=field_id,
        storage_type=storage_type, quality_grade=quality_grade,
    )