from datetime import datetime, timedelta
from fastapi import HTTPException


def _missing_duration_columns(exc: Exception) -> bool:
    text = str(exc)
    return ("stop_after" in text and "does not exist" in text) or "'42703'" in text


class IrrigationService:
    def __init__(self, sb):
        self.sb = sb

    async def stop_current(self, farm_id: str) -> dict:
        running = self.sb.table("irrigation_events").select("*") \
            .eq("farm_id", farm_id).eq("status", "running").limit(1).execute()
        if not running.data:
            return {"status": "no_running_event"}

        event = running.data[0]
        self.sb.table("irrigation_events").update({
            "status": "stopped",
            "stopped_at": datetime.utcnow().isoformat(),
        }).eq("id", event["id"]).execute()
        return {"status": "stopped", "event_id": event["id"]}

    async def cancel_next(self, farm_id: str) -> dict:
        next_event = self.sb.table("irrigation_events").select("*") \
            .eq("farm_id", farm_id).eq("status", "pending") \
            .order("scheduled_time", desc=False).limit(1).execute()
        if not next_event.data:
            return {"status": "no_pending_event"}

        event = next_event.data[0]
        self.sb.table("irrigation_events").update({"status": "cancelled"}) \
            .eq("id", event["id"]).execute()
        return {"status": "cancelled", "event_id": event["id"]}

    async def manual_on(self, farm_id: str, duration_minutes: int) -> dict:
        if duration_minutes < 1 or duration_minutes > 240:
            raise ValueError("duration_minutes must be between 1 and 240")
        now = datetime.utcnow()
        stop_after = now + timedelta(minutes=duration_minutes)
        try:
            resp = self.sb.table("irrigation_events").insert({
                "farm_id": farm_id,
                "scheduled_time": now.isoformat(),
                "started_at": now.isoformat(),
                "requested_duration_minutes": duration_minutes,
                "stop_after": stop_after.isoformat(),
                "source": "manual",
                "status": "running",
            }).execute()
        except Exception as exc:
            if not _missing_duration_columns(exc):
                raise
            raise HTTPException(
                status_code=503,
                detail=(
                    "Duration-based irrigation is not installed in the database. "
                    "Run backend/migrations/008_duration_based_irrigation.sql."
                ),
            ) from exc
        return {
            "status": "running",
            "event_id": resp.data[0]["id"],
            "duration_minutes": duration_minutes,
            "stop_after": stop_after.isoformat(),
        }
