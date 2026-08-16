from fastapi import APIRouter, HTTPException, Depends, Query
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.services.irrigation_service import IrrigationService

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

    return {
        "last_watered": last.data[0] if last.data else None,
        "next_watering": next_event.data[0] if next_event.data else None,
        "current_status": running.data[0] if running.data else None,
        "moisture_readings": list(reversed(readings.data)),
    }


@router.post("/stop-current")
async def stop_current(farm_id: str = Query(...), current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    svc = IrrigationService(sb)
    result = await svc.stop_current(farm_id)
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
    return result
