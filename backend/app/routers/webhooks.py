from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel
from datetime import datetime
from app.core.security import verify_agent_webhook, verify_hardware_webhook
from app.db.supabase_client import get_supabase_admin
from app.services.notification_service import create_notification

router = APIRouter(prefix="/webhooks", tags=["webhooks"])


class AgentResultPayload(BaseModel):
    crop_image_id: str
    farm_id: str
    agent_type: str
    result_json: dict
    status: str  # "done" | "failed"
    error: str | None = None


class HardwareStatusPayload(BaseModel):
    device_uid: str
    event_type: str  # heartbeat | motor_on | motor_off | error
    signal_strength: int | None = None
    payload: dict = {}


@router.post("/agent-result")
async def receive_agent_result(
    payload: AgentResultPayload,
    auth_info: dict = Depends(verify_agent_webhook),
):
    sb = get_supabase_admin()

    result_resp = sb.table("agent_results").insert({
        "crop_image_id": payload.crop_image_id,
        "farm_id": payload.farm_id,
        "agent_type": payload.agent_type,
        "result_json": payload.result_json,
    }).execute()
    agent_result_id = result_resp.data[0]["id"] if result_resp.data else None

    image_status = "done" if payload.status == "done" else "failed"
    sb.table("crop_images").update({"analysis_status": image_status}) \
        .eq("id", payload.crop_image_id).execute()

    if payload.status == "done" and payload.agent_type == "health":
        result = payload.result_json
        diseases = result.get("diseases_detected", [])
        health_status = result.get("health_status", "healthy")
        if diseases or health_status not in ("healthy", "optimal"):
            farm_resp = sb.table("farms").select("farmer_id").eq("id", payload.farm_id).execute()
            if farm_resp.data:
                await create_notification(
                    sb, farm_resp.data[0]["farmer_id"], "agent_result",
                    "Crop Health Alert",
                    f"Issues detected: {', '.join(diseases) if diseases else health_status}",
                    payload.crop_image_id,
                )

    return {"received": True, "agent_result_id": agent_result_id}


@router.post("/hardware-status")
async def receive_hardware_status(
    payload: HardwareStatusPayload,
    auth_info: dict = Depends(verify_hardware_webhook),
):
    sb = get_supabase_admin()

    now = datetime.utcnow().isoformat()

    # Upsert device state
    update_fields = {"last_seen_at": now}
    if payload.signal_strength is not None:
        update_fields["last_signal_strength"] = payload.signal_strength
    if payload.event_type == "motor_on":
        update_fields["motor_relay_state"] = "on"
    elif payload.event_type == "motor_off":
        update_fields["motor_relay_state"] = "off"

    sb.table("farm_devices").update(update_fields) \
        .eq("device_uid", payload.device_uid).execute()

    # Insert event
    device = sb.table("farm_devices").select("id").eq("device_uid", payload.device_uid).limit(1).execute()
    sb.table("hardware_status_events").insert({
        "farm_device_id": device.data[0]["id"] if device.data else None,
        "event_type": payload.event_type,
        "signal_strength": payload.signal_strength,
        "payload": payload.payload,
    }).execute()

    # Notify farmer on error
    if payload.event_type == "error":
        device = sb.table("farm_devices").select("farm_id").eq("device_uid", payload.device_uid).execute()
        if device.data:
            farm = sb.table("farms").select("farmer_id").eq("id", device.data[0]["farm_id"]).execute()
            if farm.data:
                error_msg = payload.payload.get("message", "Unknown hardware error")
                await create_notification(
                    sb, farm.data[0]["farmer_id"], "system",
                    "Hardware Error",
                    f"Device {payload.device_uid}: {error_msg}",
                )

    return {"received": True}
