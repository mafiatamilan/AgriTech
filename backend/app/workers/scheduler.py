from apscheduler.schedulers.asyncio import AsyncIOScheduler
from datetime import datetime, timedelta
from app.core.logging_config import get_logger
from app.db.supabase_client import get_supabase_admin
from app.services.notification_service import create_notification
from app.services.hardware_service import queue_hardware_command
from app.services.relay_service import dispatch_relay

SHELF_LIFE_WARNING_HOURS = 24
logger = get_logger("app.workers.scheduler")

scheduler = AsyncIOScheduler()


def _missing_duration_columns(exc: Exception) -> bool:
    text = str(exc)
    return "stop_after" in text and "does not exist" in text or "'42703'" in text


async def check_irrigation_schedule():
    sb = get_supabase_admin()
    now = datetime.utcnow().isoformat()

    try:
        due_running = sb.table("irrigation_events").select("*") \
            .eq("status", "running") \
            .not_.is_("stop_after", "null") \
            .lte("stop_after", now).limit(20).execute()
    except Exception as exc:
        if not _missing_duration_columns(exc):
            raise
        logger.warning(
            "Duration-based irrigation columns are missing. "
            "Run backend/migrations/008_duration_based_irrigation.sql."
        )
        due_running = None

    for event in (due_running.data if due_running else []) or []:
        sb.table("irrigation_events").update({
            "status": "completed",
            "stopped_at": now,
        }).eq("id", event["id"]).execute()

        queue_hardware_command(sb, event["farm_id"], "off", event["id"])
        await dispatch_relay("off")

        farm = sb.table("farms").select("farmer_id").eq("id", event["farm_id"]).execute()
        if farm.data:
            await create_notification(
                sb, farm.data[0]["farmer_id"], "watering",
                "Irrigation Completed",
                "Watering stopped after the selected duration.",
                event["id"],
            )

    upcoming = sb.table("irrigation_events").select("*") \
        .eq("status", "pending") \
        .lte("scheduled_time", now).limit(10).execute()

    for event in upcoming.data:
        update = {"status": "running", "started_at": now}
        duration = event.get("requested_duration_minutes")
        if duration and not event.get("stop_after"):
            update["stop_after"] = (
                datetime.utcnow() + timedelta(minutes=int(duration))
            ).isoformat()
        try:
            sb.table("irrigation_events").update(update) \
                .eq("id", event["id"]).execute()
        except Exception as exc:
            if not _missing_duration_columns(exc):
                raise
            legacy_update = {"status": "running", "started_at": now}
            sb.table("irrigation_events").update(legacy_update) \
                .eq("id", event["id"]).execute()

        queue_hardware_command(
            sb,
            event["farm_id"],
            "on",
            event["id"],
            duration_minutes=event.get("requested_duration_minutes"),
        )

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
        sb.table("notifications").delete() \
            .eq("related_id", dr["id"]).eq("type", "shelf_life_expiring").execute()
        await create_notification(
            sb, dr["farmer_id"], "match",
            "Request Expired",
            f"Your {dr['crop_name']} request has expired",
            dr["id"],
        )


async def check_shelf_life_warnings():
    sb = get_supabase_admin()
    now = datetime.utcnow()
    warning_window = now + timedelta(hours=SHELF_LIFE_WARNING_HOURS)

    expiring = sb.table("demand_requests").select("*") \
        .eq("status", "open") \
        .not_.is_("shelf_life_expiry", "null") \
        .lte("shelf_life_expiry", warning_window.isoformat()) \
        .gte("shelf_life_expiry", now.isoformat()).limit(20).execute()

    for dr in expiring.data:
        existing = sb.table("notifications").select("id") \
            .eq("related_id", dr["id"]) \
            .eq("type", "shelf_life_expiring") \
            .is_("read_at", "null").limit(1).execute()
        if existing.data:
            continue

        await create_notification(
            sb, dr["farmer_id"], "shelf_life_expiring",
            "Shelf Life Expiring Soon",
            f"Your {dr['crop_name']} listing expires soon. Extend shelf life or it will be marked expired.",
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


async def run_agent_jobs_per_farm():
    from app.agents.graph import run_farm_graph

    sb = get_supabase_admin()
    farms = sb.table("farms").select("id, farmer_id").limit(100).execute()
    for farm in farms.data or []:
        # LangGraph is the canonical execution path: one agent_run_id ties
        # together every agent_result / decision / impact metric / command.
        try:
            await run_farm_graph(sb, farm["id"], farm["farmer_id"])
        except Exception:
            # per-farm isolation: one farm's failure never blocks the rest
            continue


def start_scheduler():
    scheduler.add_job(check_irrigation_schedule, "interval", minutes=1, id="irrigation_check")
    scheduler.add_job(check_shelf_life_expiry, "interval", minutes=5, id="shelf_life_check")
    scheduler.add_job(check_shelf_life_warnings, "interval", minutes=10, id="shelf_life_warning")
    scheduler.add_job(check_new_matches, "interval", minutes=2, id="match_check")
    scheduler.add_job(run_agent_jobs_per_farm, "interval", minutes=15, id="agent_jobs")
    scheduler.start()


def stop_scheduler():
    scheduler.shutdown(wait=False)
