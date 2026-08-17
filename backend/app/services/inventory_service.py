"""Inventory agent orchestration.

Creates/updates the existing `inventory` table (no `inventory_batches`
duplicate), runs the InventoryAgent, persists shelf-life in
`inventory_statuses`, updates inventory status, and notifies on shelf-life risk.
"""

from datetime import date, datetime

from app.agents.runtime import agents
from app.services.notification_service import create_notification
from app.services.weather_service import get_weather_snapshot


async def record_inventory(
    sb,
    farmer_id: str,
    farm_id: str,
    crop_name: str,
    quantity: float,
    harvested_date: str,
    field_id: str | None = None,
    storage_type: str | None = None,
    quality_grade: str | None = None,
) -> dict:
    biz = agents()["business"]
    now_iso = datetime.utcnow().isoformat()

    existing = sb.table("inventory").select("*") \
        .eq("farm_id", farm_id).eq("crop_name", crop_name).limit(1).execute()
    if existing.data:
        inv = existing.data[0]
        sb.table("inventory").update({
            "quantity": quantity,
            "harvested_date": harvested_date,
            "storage_type": storage_type or inv.get("storage_type"),
            "quality_grade": quality_grade or inv.get("quality_grade") or "A",
            "field_id": field_id,
            "status": "available",
            "updated_at": now_iso,
        }).eq("id", inv["id"]).execute()
        inventory_id = inv["id"]
    else:
        resp = sb.table("inventory").insert({
            "farm_id": farm_id,
            "crop_name": crop_name,
            "quantity": quantity,
            "harvested_date": harvested_date,
            "storage_type": storage_type,
            "quality_grade": quality_grade or "A",
            "status": "available",
            "field_id": field_id,
        }).execute()
        inventory_id = resp.data[0]["id"]

    weather = await get_weather_snapshot(sb, farm_id, field_id=field_id, crop=crop_name)

    try:
        storage_enum = biz.models.StorageType(storage_type) if storage_type else biz.models.StorageType.AMBIENT
    except ValueError:
        storage_enum = biz.models.StorageType.AMBIENT

    batch = biz.models.InventoryBatch(
        batch_id=inventory_id,
        crop=crop_name,
        quantity_kg=float(quantity),
        harvest_date=_as_date(harvested_date) or date.today(),
        storage_type=storage_enum,
        quality_grade=quality_grade or "A",
        farm_id=farm_id,
    )
    bw = biz.models.WeatherSnapshot(
        avg_temp_c=float(weather.get("avg_temp_c") or 0),
        max_temp_c=float(weather.get("max_temp_c") or 0),
        humidity_pct=float(weather.get("humidity_pct") or 0),
        rainfall_mm=float(weather.get("rainfall_mm_today") or 0),
        condition=weather.get("condition") or "clear",
    )

    try:
        status = biz.InventoryAgent().review_batch(batch=batch, weather=bw)
    except Exception:
        # ponytail: unknown crop profile -> no shelf-life estimate, keep listing
        return {"inventory_id": inventory_id, "status": "available", "shelf_life": None}

    shelf = status.shelf_life
    sb.table("inventory_statuses").insert({
        "inventory_id": inventory_id,
        "weather_snapshot_id": weather.get("id"),
        "estimated_shelf_life_days": shelf.estimated_shelf_life_days,
        "remaining_shelf_life_days": shelf.remaining_shelf_life_days,
        "sell_by_date": shelf.sell_by_date.isoformat(),
        "urgency": shelf.urgency.value,
        "spoilage_risk": shelf.spoilage_risk,
        "recommendation": shelf.recommendation,
        "factors": list(shelf.factors),
    }).execute()

    inv_status = "expired" if shelf.remaining_shelf_life_days <= 0 else "available"
    sb.table("inventory").update({"status": inv_status}).eq("id", inventory_id).execute()

    sb.table("agent_results").insert({
        "farm_id": farm_id,
        "field_id": field_id,
        "agent_type": "inventory",
        "result_json": {
            "crop_name": crop_name,
            "quantity": quantity,
            "status": inv_status,
            "low_stock_alert": float(quantity) < 5,
            "shelf_life_days": shelf.estimated_shelf_life_days,
            "remaining_shelf_life_days": shelf.remaining_shelf_life_days,
            "urgency": shelf.urgency.value,
        },
        "model_name": "InventoryAgent",
        "model_version": "1",
    }).execute()

    if shelf.urgency.value in ("high", "urgent", "expired_risk"):
        await create_notification(
            sb, farmer_id, "shelf_life_expiring",
            "Shelf Life Alert",
            f"{crop_name} needs attention: {shelf.recommendation}",
            inventory_id,
        )

    return {
        "inventory_id": inventory_id,
        "status": inv_status,
        "shelf_life": shelf.remaining_shelf_life_days,
        "urgency": shelf.urgency.value,
    }


def _as_date(value):
    if not value:
        return None
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except (ValueError, TypeError):
        return None