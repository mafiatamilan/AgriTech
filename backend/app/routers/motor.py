from datetime import datetime, timezone
import hashlib

from fastapi import APIRouter, HTTPException, Depends, Query, Request, Response
from app.core.deps import get_current_farmer
from app.core.config import get_settings
from app.db.supabase_client import get_supabase, get_supabase_admin
from app.services.irrigation_service import IrrigationService
from app.services.hardware_service import queue_hardware_command

settings = get_settings()
router = APIRouter(prefix="/motor", tags=["motor"])


@router.get("/status")
async def motor_status(
    farm_id: str = Query(...),
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    svc = IrrigationService(sb)

    last = sb.table("irrigation_events").select("*") \
        .eq("farm_id", farm_id).in_("status", ["completed", "stopped"]) \
        .order("stopped_at", desc=True).limit(1).execute()

    next_event = sb.table("irrigation_events").select("*") \
        .eq("farm_id", farm_id).eq("status", "pending") \
        .order("scheduled_time", desc=False).limit(1).execute()

    running = sb.table("irrigation_events").select("*") \
        .eq("farm_id", farm_id).eq("status", "running").limit(1).execute()

    readings = sb.table("sensor_readings").select("*") \
        .eq("farm_id", farm_id).order("recorded_at", desc=True).limit(24).execute()

    device = sb.table("farm_devices").select("device_uid, last_signal_strength, motor_relay_state, last_seen_at") \
        .eq("farm_id", farm_id).limit(1).execute()

    device_row = device.data[0] if device.data else None

    return {
        "last_watered": last.data[0] if last.data else None,
        "next_watering": next_event.data[0] if next_event.data else None,
        "current_status": running.data[0] if running.data else None,
        "moisture_readings": list(reversed(readings.data)),
        "signal_strength": device_row["last_signal_strength"] if device_row else None,
        "motor_relay_state": (device_row["motor_relay_state"] == "on") if device_row else False,
        "device": device_row,
    }


@router.post("/stop-current")
async def stop_current(farm_id: str = Query(...), current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    svc = IrrigationService(sb)
    result = await svc.stop_current(farm_id)
    if result.get("status") == "stopped":
        queue_hardware_command(sb, farm_id, "off")
    return result


@router.post("/cancel-next")
async def cancel_next(farm_id: str = Query(...), current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    svc = IrrigationService(sb)
    return await svc.cancel_next(farm_id)


@router.post("/on")
async def manual_on(farm_id: str = Query(...), current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    svc = IrrigationService(sb)
    result = await svc.manual_on(farm_id)
    if result.get("status") == "running":
        queue_hardware_command(sb, farm_id, "on")
    return result


@router.post("/dispatch")
async def dispatch_command(farm_id: str, action: str = Query(..., pattern="^(on|off)$")):
    sb = get_supabase_admin()
    queue_hardware_command(sb, farm_id, action)
    return {"dispatched": True, "action": action}


@router.get("/pending-command")
async def pending_command(device_uid: str = Query(...), request: Request = None):
    sb = get_supabase_admin()

    device = sb.table("farm_devices").select("id, device_secret_hash") \
        .eq("device_uid", device_uid).limit(1).execute()
    if not device.data:
        raise HTTPException(status_code=404, detail="Device not found")

    secret = request.headers.get("X-Agent-Secret") if request else None
    if not secret:
        raise HTTPException(status_code=401, detail="Missing device secret")
    if hashlib.sha256(secret.encode()).hexdigest() != device.data[0]["device_secret_hash"]:
        raise HTTPException(status_code=401, detail="Invalid device secret")

    cmd = sb.table("mqtt_commands").select("*") \
        .eq("farm_device_id", device.data[0]["id"]) \
        .in_("publish_status", ["pending", "sent"]) \
        .order("issued_at", desc=False).limit(1).execute()

    if not cmd.data:
        return Response(status_code=204)

    command = cmd.data[0]
    sb.table("mqtt_commands").update({
        "publish_status": "sent",
        "sent_at": datetime.now(timezone.utc).isoformat(),
    }).eq("id", command["id"]).execute()

    return {
        "action": command["payload"].get("action", "status_request"),
        "issued_at": command["issued_at"],
    }