"""Hardware command queueing.

The MVP transport is HTTP polling: the ESP32 polls `GET /motor/pending-command`
and the backend writes to the `mqtt_commands` table (canonical/audit). No MQTT
broker is required.
"""

from datetime import datetime


def queue_hardware_command(
    sb, farm_id: str, action: str, irrigation_event_id: str | None = None,
    agent_run_id: str | None = None,
    duration_minutes: int | None = None,
) -> dict | None:
    """Queue a validated actuator command for the farm's device.

    Returns None when no device is paired — commands are never issued for a
    missing device. `action` is validated (on/off only).
    """
    if action not in ("on", "off"):
        raise ValueError(f"invalid hardware action: {action!r}")

    device = sb.table("farm_devices").select("id, device_uid") \
        .eq("farm_id", farm_id).limit(1).execute()
    if not device.data:
        return None
    d = device.data[0]
    payload = {"action": action}
    if duration_minutes is not None:
        payload["duration_minutes"] = duration_minutes

    resp = sb.table("mqtt_commands").insert({
        "farm_id": farm_id,
        "farm_device_id": d["id"],
        "irrigation_event_id": irrigation_event_id,
        "command_type": "motor_on" if action == "on" else "motor_off",
        "payload": payload,
        "publish_status": "pending",
        "agent_run_id": agent_run_id,
    }).execute()
    return resp.data[0] if resp.data else None


def acknowledge_commands_for_device(sb, device_id: str) -> None:
    """Mark pending/sent commands as acknowledged once the device confirms."""
    sb.table("mqtt_commands").update({
        "publish_status": "acknowledged",
        "acknowledged_at": datetime.utcnow().isoformat(),
    }).eq("farm_device_id", device_id).in_("publish_status", ["pending", "sent"]).execute()
