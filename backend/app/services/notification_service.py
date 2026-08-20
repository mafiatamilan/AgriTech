from datetime import datetime
import httpx

from app.core.config import get_settings

settings = get_settings()


async def create_notification(
    sb,
    farmer_id: str,
    type: str,
    title: str,
    body: str,
    related_id: str | None = None,
) -> dict:
    resp = sb.table("notifications").insert({
        "farmer_id": farmer_id,
        "type": type,
        "title": title,
        "body": body,
        "related_id": related_id,
    }).execute()
    notification = resp.data[0] if resp.data else {}
    await _send_push(
        sb,
        farmer_id,
        title,
        body,
        {"type": type, "related_id": related_id or ""},
    )
    return notification


async def _send_push(sb, farmer_id: str, title: str, body: str, data: dict) -> None:
    if not settings.FCM_SERVER_KEY:
        return
    tokens = sb.table("device_push_tokens").select("token") \
        .eq("farmer_id", farmer_id).execute()
    token_values = [
        row.get("token")
        for row in tokens.data or []
        if row.get("token")
    ]
    if not token_values:
        return

    payload = {
        "registration_ids": token_values[:500],
        "notification": {"title": title, "body": body},
        "data": data,
        "priority": "high",
    }
    headers = {
        "Authorization": f"key={settings.FCM_SERVER_KEY}",
        "Content-Type": "application/json",
    }
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            await client.post(
                "https://fcm.googleapis.com/fcm/send",
                json=payload,
                headers=headers,
            )
    except Exception:
        # The in-app notification row is the source of truth; push transport
        # failures should not break irrigation or marketplace workflows.
        return
