import hashlib
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.models.farm import (
    FarmCreate,
    FarmUpdate,
    FieldAreaCreate,
    FieldAreaUpdate,
)
from app.services.weather_service import get_weather_snapshot

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
        row["latitude"] = farm.latitude
        row["longitude"] = farm.longitude
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
        # keep numeric columns in sync so the weather service can read them
        update_data["latitude"] = farm.latitude
        update_data["longitude"] = farm.longitude
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


def _owned_farm(sb, farm_id: str, farmer_id: str) -> dict:
    farm = sb.table("farms").select("*").eq("id", farm_id).eq("farmer_id", farmer_id).execute()
    if not farm.data:
        raise HTTPException(status_code=404, detail="Farm not found")
    return farm.data[0]


@router.get("/{farm_id}/fields")
async def list_fields(farm_id: str, current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    _owned_farm(sb, farm_id, current_farmer["id"])
    resp = sb.table("field_area").select("*").eq("farm_id", farm_id).order("updated_at", desc=False).execute()
    return resp.data


@router.post("/{farm_id}/fields")
async def create_field(
    farm_id: str,
    req: FieldAreaCreate,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    _owned_farm(sb, farm_id, current_farmer["id"])
    row = req.model_dump(exclude_unset=True)
    row["farm_id"] = farm_id
    resp = sb.table("field_area").insert(row).execute()
    if not resp.data:
        raise HTTPException(status_code=400, detail="Failed to create field")
    return resp.data[0]


@router.patch("/{farm_id}/fields/{field_id}")
async def update_field(
    farm_id: str,
    field_id: str,
    req: FieldAreaUpdate,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    _owned_farm(sb, farm_id, current_farmer["id"])
    resp = sb.table("field_area").update(req.model_dump(exclude_unset=True)) \
        .eq("id", field_id).eq("farm_id", farm_id).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Field not found")
    return resp.data[0]


@router.get("/{farm_id}/weather")
async def farm_weather(farm_id: str, current_farmer: dict = Depends(get_current_farmer)):
    """Current weather for a farm, via the existing weather service.

    Returns the fresh snapshot plus the latest irrigation decision so the
    Home screen can show both the forecast and the irrigation insight.
    """
    sb = get_supabase()
    farm = _owned_farm(sb, farm_id, current_farmer["id"])

    weather = await get_weather_snapshot(
        sb, farm_id,
        farm_lat=farm.get("latitude"), farm_lon=farm.get("longitude"),
    )

    latest = sb.table("agent_results").select("result_json, created_at") \
        .eq("farm_id", farm_id).eq("agent_type", "irrigation") \
        .order("created_at", desc=True).limit(1).execute()
    irrigation = latest.data[0]["result_json"] if latest.data else None

    return {
        **weather,
        "irrigation": irrigation,
    }
