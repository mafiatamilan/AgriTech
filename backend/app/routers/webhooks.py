from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel
from datetime import datetime, timezone
from app.core.security import verify_agent_webhook, verify_hardware_webhook
from app.db.supabase_client import get_supabase_admin
from app.services.notification_service import create_notification
from app.services.hardware_service import acknowledge_commands_for_device

router = APIRouter(prefix="/webhooks", tags=["webhooks"])


class AgentResultPayload(BaseModel):
    model_config = {"protected_namespaces": ()}

    crop_image_id: str | None = None
    farm_id: str
    agent_type: str
    result_json: dict
    status: str  # "done" | "failed"
    error: str | None = None
    field_id: str | None = None
    image_upload_id: str | None = None
    model_name: str | None = None
    model_version: str | None = None
    agent_run_id: str | None = None


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
        "image_upload_id": payload.image_upload_id or payload.crop_image_id,
        "farm_id": payload.farm_id,
        "field_id": payload.field_id,
        "agent_type": payload.agent_type,
        "result_json": payload.result_json,
        "model_name": payload.model_name,
        "model_version": payload.model_version,
        "agent_run_id": payload.agent_run_id,
    }).execute()
    agent_result_id = result_resp.data[0]["id"] if result_resp.data else None

    image_status = "done" if payload.status == "done" else "failed"
    if payload.crop_image_id:
        update = {"analysis_status": image_status}
        if payload.status == "failed" and payload.error:
            update["failure_reason"] = payload.error[:500]
        sb.table("crop_images").update(update) \
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

    now = datetime.now(timezone.utc).isoformat()

    device = sb.table("farm_devices").select("*") \
        .eq("device_uid", payload.device_uid).limit(1).execute()
    if not device.data:
        return {"received": True, "device": None}

    dev = device.data[0]

    update_fields = {
        "last_seen_at": now,
        "health_status": payload.payload.get("health_status", "healthy"),
        "last_error": payload.payload.get("error") or None,
    }
    if payload.signal_strength is not None:
        update_fields["last_signal_strength"] = payload.signal_strength
    if payload.event_type == "motor_on":
        update_fields["motor_relay_state"] = "on"
    elif payload.event_type == "motor_off":
        update_fields["motor_relay_state"] = "off"
    for out_key, in_key in (("last_moisture_pct", "moisture_pct"),
                            ("last_temperature_c", "temperature_c"),
                            ("last_humidity_pct", "humidity_pct")):
        if payload.payload.get(in_key) is not None:
            update_fields[out_key] = payload.payload[in_key]

    sb.table("farm_devices").update(update_fields) \
        .eq("id", dev["id"]).execute()

    status_resp = sb.table("hardware_status_events").insert({
        "farm_device_id": dev["id"],
        "event_type": payload.event_type,
        "signal_strength": payload.signal_strength,
        "moisture_pct": payload.payload.get("moisture_pct"),
        "temperature_c": payload.payload.get("temperature_c"),
        "humidity_pct": payload.payload.get("humidity_pct"),
        "battery_voltage": payload.payload.get("battery_voltage"),
        "firmware_version": payload.payload.get("firmware_version"),
        "payload": payload.payload,
    }).execute()

    moisture_pct = payload.payload.get("moisture_pct")
    if moisture_pct is not None and dev.get("farm_id"):
        sb.table("sensor_readings").insert({
            "farm_id": dev["farm_id"],
            "moisture_pct": moisture_pct,
            "signal_strength": payload.signal_strength,
            "recorded_at": now,
        }).execute()

    if payload.event_type in ("motor_on", "motor_off"):
        acknowledge_commands_for_device(sb, dev["id"])

    if payload.event_type == "error":
        farm = sb.table("farms").select("farmer_id").eq("id", dev["farm_id"]).execute()
        if farm.data:
            error_msg = payload.payload.get("message", "Unknown hardware error")
            await create_notification(
                sb, farm.data[0]["farmer_id"], "device_status",
                "Hardware Error",
                f"Device {payload.device_uid}: {error_msg}",
            )

    return {"received": True}