from fastapi import APIRouter, HTTPException, Depends
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.models.farm import FarmCreate, FarmUpdate

router = APIRouter(prefix="/farms", tags=["farms"])


@router.get("")
async def list_farms(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("farms").select("*").eq("farmer_id", current_farmer["id"]).execute()
    return resp.data


@router.post("")
async def create_farm(farm: FarmCreate, current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    row = {"farmer_id": current_farmer["id"], "name": farm.name}
    if farm.latitude is not None and farm.longitude is not None:
        row["location"] = f"POINT({farm.longitude} {farm.latitude})"
    resp = sb.table("farms").insert(row).execute()
    return resp.data[0]


@router.get("/{farm_id}")
async def get_farm(farm_id: str, current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("farms").select("*").eq("id", farm_id).eq("farmer_id", current_farmer["id"]).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Farm not found")
    return resp.data[0]


@router.patch("/{farm_id}")
async def update_farm(farm_id: str, farm: FarmUpdate, current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    update_data = farm.model_dump(exclude_unset=True)
    if farm.latitude is not None and farm.longitude is not None:
        update_data["location"] = f"POINT({farm.longitude} {farm.latitude})"
        del update_data["latitude"]
        del update_data["longitude"]
    resp = sb.table("farms").update(update_data).eq("id", farm_id).eq("farmer_id", current_farmer["id"]).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Farm not found")
    return resp.data[0]
