from pydantic import BaseModel
from fastapi import APIRouter, Depends
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase

router = APIRouter(prefix="/notifications", tags=["notifications"])


class PushTokenRequest(BaseModel):
    token: str
    platform: str | None = None


@router.get("")
async def list_notifications(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("notifications").select("*") \
        .eq("farmer_id", current_farmer["id"]) \
        .order("created_at", desc=True).limit(50).execute()
    return resp.data


@router.patch("/{notification_id}/read")
async def mark_read(notification_id: str, current_farmer: dict = Depends(get_current_farmer)):
    from datetime import datetime
    sb = get_supabase()
    sb.table("notifications").update({"read_at": datetime.utcnow().isoformat()}) \
        .eq("id", notification_id).eq("farmer_id", current_farmer["id"]).execute()
    return {"status": "read"}


@router.post("/push-token")
async def register_push_token(req: PushTokenRequest, current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    sb.table("device_push_tokens").upsert({
        "farmer_id": current_farmer["id"],
        "token": req.token,
        "platform": req.platform,
    }, on_conflict="token").execute()
    return {"status": "registered"}
