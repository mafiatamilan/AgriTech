from fastapi import APIRouter, Depends
from pydantic import BaseModel
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase

router = APIRouter(prefix="/settings", tags=["settings"])


class SettingsUpdate(BaseModel):
    preferred_language: str | None = None
    notification_watering: bool | None = None
    notification_match: bool | None = None
    notification_system: bool | None = None


@router.get("")
async def get_settings(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("farmers").select("preferred_language") \
        .eq("id", current_farmer["id"]).execute()
    lang = resp.data[0]["preferred_language"] if resp.data else "en"
    return {
        "preferred_language": lang,
        "notification_watering": True,
        "notification_match": True,
        "notification_system": True,
    }


@router.patch("")
async def update_settings(req: SettingsUpdate, current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    update_data = req.model_dump(exclude_unset=True)
    lang = update_data.pop("preferred_language", None)
    if lang:
        sb.table("farmers").update({"preferred_language": lang}) \
            .eq("id", current_farmer["id"]).execute()
    return {"status": "updated"}
