from datetime import datetime
from fastapi import APIRouter, HTTPException, Depends, Query
from pydantic import BaseModel
from app.core.deps import get_current_farmer
from app.core.config import get_settings
from app.db.supabase_client import get_supabase, get_supabase_admin
from app.services.irrigation_service import IrrigationService

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
        .eq("farm_id", farm_id).eq("status", "completed") \
        .order("stopped_at", desc=True).limit(1).execute()

    next_event = sb.table("irrigation_events").select("*") \
        .eq("farm_id", farm_id).eq("status", "pending") \
        .order("scheduled_time", desc=False).limit(1).execute()

    running = sb.table("irrigation_events").select("*") \
        .eq("farm_id", farm_id).eq("status", "running").limit(1).execute()

    readings = sb.table("sensor_readings").select("*") \
        .eq("farm_id", farm_id).order("recorded_at", desc=True).limit(24).execute()

    # Include device info
    device = sb.table("farm_devices").select("device_uid, last_signal_strength, motor_relay_state, last_seen_at") \
        .eq("farm_id", farm_id).limit(1).execute()

    return {
        "last_watered": last.data[0] if last.data else None,
        "next_watering": next_event.data[0] if next_event.data else None,
        "current_status": running.data[0] if running.data else None,
        "moisture_readings": list(reversed(readings.data)),
        "device": device.data[0] if device.data else None,
    }


@router.post("/stop-current")
async def stop_current(farm_id: str = Query(...), current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    svc = IrrigationService(sb)
    result = await svc.stop_current(farm_id)
    # Queue off command if device exists
    if result.get("status") == "stopped":
        _queue_command(sb, farm_id, "off")
    return result


@router.post("/cancel-next")
async def cancel_next(farm_id: str = Query(...), current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    svc = IrrigationService(sb)
    result = await svc.cancel_next(farm_id)
    return result


@router.post("/on")
async def manual_on(farm_id: str = Query(...), current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    svc = IrrigationService(sb)
    result = await svc.manual_on(farm_id)
    if result.get("status") == "running":
        _queue_command(sb, farm_id, "on")
    return result


@router.post("/dispatch")
async def dispatch_command(farm_id: str, action: str = Query(..., regex="^(on|off)$")):
    sb = get_supabase_admin()
    _queue_command(sb, farm_id, action)
    return {"dispatched": True, "action": action}


def _queue_command(sb, farm_id: str, action: str):
    device = sb.table("farm_devices").select("device_uid") \
        .eq("farm_id", farm_id).limit(1).execute()
    if device.data:
        sb.table("hardware_command_queue").insert({
            "device_uid": device.data[0]["device_uid"],
            "action": action,
        }).execute()


@router.get("/pending-command")
async def pending_command(device_uid: str = Query(...)):
    sb = get_supabase_admin()
    cmd = sb.table("hardware_command_queue").select("*") \
        .eq("device_uid", device_uid).is_("delivered_at", "null") \
        .order("issued_at", desc=False).limit(1).execute()
    if not cmd.data:
        raise HTTPException(status_code=204, detail="No pending commands")
    # Mark as delivered
    sb.table("hardware_command_queue").update({"delivered_at": datetime.utcnow().isoformat()}) \
        .eq("id", cmd.data[0]["id"]).execute()
    return {"action": cmd.data[0]["action"], "issued_at": cmd.data[0]["issued_at"]}
