import hashlib
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.models.farm import FarmCreate, FarmUpdate

router = APIRouter(prefix="/farms", tags=["farms"])


class DevicePairRequest(BaseModel):
    device_uid: str
    device_secret: str


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


@router.post("/{farm_id}/devices")
async def pair_device(
    farm_id: str,
    req: DevicePairRequest,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()

    # Verify farm belongs to farmer
    farm = sb.table("farms").select("id").eq("id", farm_id).eq("farmer_id", current_farmer["id"]).execute()
    if not farm.data:
        raise HTTPException(status_code=404, detail="Farm not found")

    secret_hash = hashlib.sha256(req.device_secret.encode()).hexdigest()

    resp = sb.table("farm_devices").insert({
        "farm_id": farm_id,
        "device_uid": req.device_uid,
        "device_secret_hash": secret_hash,
    }).execute()

    if not resp.data:
        raise HTTPException(status_code=400, detail="Failed to pair device")

    device = resp.data[0]
    # Don't return the hash
    device.pop("device_secret_hash", None)
    return device
