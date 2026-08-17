from datetime import datetime


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

    async def manual_on(self, farm_id: str) -> dict:
        resp = self.sb.table("irrigation_events").insert({
            "farm_id": farm_id,
            "scheduled_time": datetime.utcnow().isoformat(),
            "started_at": datetime.utcnow().isoformat(),
            "status": "running",
        }).execute()
        return {"status": "running", "event_id": resp.data[0]["id"]}
