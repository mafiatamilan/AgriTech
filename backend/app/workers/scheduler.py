from apscheduler.schedulers.asyncio import AsyncIOScheduler
from datetime import datetime
from app.db.supabase_client import get_supabase_admin
from app.services.notification_service import create_notification


scheduler = AsyncIOScheduler()


async def check_irrigation_schedule():
    sb = get_supabase_admin()
    now = datetime.utcnow().isoformat()
    upcoming = sb.table("irrigation_events").select("*") \
        .eq("status", "pending") \
        .lte("scheduled_time", now).limit(10).execute()

    for event in upcoming.data:
        sb.table("irrigation_events").update({"status": "running", "started_at": now}) \
            .eq("id", event["id"]).execute()

        farm = sb.table("farms").select("farmer_id").eq("id", event["farm_id"]).execute()
        if farm.data:
            await create_notification(
                sb, farm.data[0]["farmer_id"], "watering",
                "Irrigation Started",
                f"Watering has started for your farm",
                event["id"],
            )


async def check_shelf_life_expiry():
    sb = get_supabase_admin()
    now = datetime.utcnow().isoformat()
    expired = sb.table("demand_requests").select("*") \
        .eq("status", "open") \
        .not_.is_("shelf_life_expiry", "null") \
        .lte("shelf_life_expiry", now).limit(10).execute()

    for dr in expired.data:
        sb.table("demand_requests").update({"status": "expired"}) \
            .eq("id", dr["id"]).execute()
        await create_notification(
            sb, dr["farmer_id"], "match",
            "Request Expired",
            f"Your {dr['crop_name']} request has expired",
            dr["id"],
        )


async def check_new_matches():
    sb = get_supabase_admin()
    recent = sb.table("rescue_matches").select("*") \
        .eq("status", "proposed").limit(10).execute()

    for match in recent.data:
        dr = sb.table("demand_requests").select("farmer_id,crop_name") \
            .eq("id", match["demand_request_id"]).execute()
        if dr.data:
            await create_notification(
                sb, dr.data[0]["farmer_id"], "match",
                "New Match Found",
                f"A buyer is interested in your {dr.data[0]['crop_name']}",
                match["id"],
            )


def start_scheduler():
    scheduler.add_job(check_irrigation_schedule, "interval", minutes=1, id="irrigation_check")
    scheduler.add_job(check_shelf_life_expiry, "interval", minutes=5, id="shelf_life_check")
    scheduler.add_job(check_new_matches, "interval", minutes=2, id="match_check")
    scheduler.start()


def stop_scheduler():
    scheduler.shutdown(wait=False)
