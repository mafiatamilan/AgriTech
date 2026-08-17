from datetime import datetime


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
    return resp.data[0] if resp.data else {}
