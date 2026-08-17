from fastapi import APIRouter, Depends
from pydantic import BaseModel
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase

router = APIRouter(prefix="/settings", tags=["settings"])


class SettingsUpdate(BaseModel):
    preferred_language: str | None = None
    soil_type: str | None = None
    area_locality: str | None = None
    notification_watering: bool | None = None
    notification_match: bool | None = None
    notification_system: bool | None = None


@router.get("")
async def get_settings(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("farmers").select("preferred_language, soil_type, area_locality") \
        .eq("id", current_farmer["id"]).execute()
    if not resp.data:
        return {
            "preferred_language": "en",
            "soil_type": None,
            "area_locality": None,
            "notification_watering": True,
            "notification_match": True,
            "notification_system": True,
        }
    row = resp.data[0]
    return {
        "preferred_language": row.get("preferred_language", "en"),
        "soil_type": row.get("soil_type"),
        "area_locality": row.get("area_locality"),
        "notification_watering": True,
        "notification_match": True,
        "notification_system": True,
    }


@router.patch("")
async def update_settings(req: SettingsUpdate, current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    update_data = req.model_dump(exclude_unset=True)
    # Persist DB-backed fields
    db_fields = {}
    for key in ("preferred_language", "soil_type", "area_locality"):
        if key in update_data:
            db_fields[key] = update_data.pop(key)
    if db_fields:
        sb.table("farmers").update(db_fields) \
            .eq("id", current_farmer["id"]).execute()
    # notification_* fields accepted but not yet persisted
    return {"status": "updated"}
