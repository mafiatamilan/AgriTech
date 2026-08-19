from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.models.market import DemandRequestCreate, CropMatchResponse
from app.agents.demand_matching import run_demand_matching
from app.services.notification_service import create_notification

router = APIRouter(prefix="/market", tags=["market"])


class ExtendShelfLifeRequest(BaseModel):
    additional_days: int


def _strip(match: dict) -> dict:
    # ponytail: internal match_score kept in DB, never shown to farmer
    if isinstance(match, dict):
        match.pop("match_score", None)
    return match


def _as_float(value) -> float:
    if value is None:
        return 0.0
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _enrich_buyer_info(sb, buyer_info: dict) -> dict:
    if not isinstance(buyer_info, dict):
        return {}
    buyer_id = buyer_info.get("buyer_farmer_id")
    if not buyer_id:
        return buyer_info
    vendor = sb.table("vendors").select("business_name, contact_phone, contact_email, address") \
        .eq("id", buyer_id).limit(1).execute()
    if vendor.data:
        row = vendor.data[0]
        buyer_info["buyer_name"] = row.get("business_name") or buyer_info.get("buyer_name") or "Vendor"
        buyer_info["buyer_phone"] = row.get("contact_phone") or buyer_info.get("buyer_phone")
        buyer_info["buyer_email"] = row.get("contact_email") or buyer_info.get("buyer_email")
        buyer_info["buyer_address"] = row.get("address") or buyer_info.get("buyer_address")
    return buyer_info


def _reduce_inventory_for_sale(sb, farmer_id: str, crop_name: str, quantity_kg: float) -> None:
    farms = sb.table("farms").select("id").eq("farmer_id", farmer_id).execute()
    farm_ids = [farm["id"] for farm in farms.data or []]
    if not farm_ids:
        return
    remaining_to_reduce = quantity_kg
    rows = sb.table("inventory").select("*") \
        .in_("farm_id", farm_ids) \
        .eq("crop_name", crop_name) \
        .gt("quantity", 0) \
        .order("harvested_date", desc=False) \
        .execute()
    for item in rows.data or []:
        if remaining_to_reduce <= 0:
            break
        current_qty = _as_float(item.get("quantity"))
        if current_qty <= 0:
            continue
        reduce_by = min(current_qty, remaining_to_reduce)
        next_qty = current_qty - reduce_by
        update = {"quantity": next_qty}
        if next_qty <= 0:
            update["status"] = "sold"
        sb.table("inventory").update(update).eq("id", item["id"]).execute()
        remaining_to_reduce -= reduce_by


@router.get("/address-prompt")
async def address_prompt(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("farms").select("id, name, location") \
        .eq("farmer_id", current_farmer["id"]).execute()
    return {"farms": resp.data}


@router.post("/crop-match", response_model=CropMatchResponse)
async def crop_match(
    req: DemandRequestCreate,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()

    # Try to get shelf life from inventory_statuses (actual agent data)
    shelf_life_days = req.shelf_life_days
    shelf_life_expiry = None
    quantity_kg = req.quantity_kg

    if quantity_kg is not None and quantity_kg <= 0:
        raise HTTPException(status_code=422, detail="quantity_kg must be greater than zero")

    # Inventory is scoped through farms; it does not have a farmer_id column.
    farmer_farms = sb.table("farms").select("id") \
        .eq("farmer_id", current_farmer["id"]).execute()
    farm_ids = [farm["id"] for farm in farmer_farms.data or []]
    inv_resp = sb.table("inventory").select("id") \
        .in_("farm_id", farm_ids) \
        .eq("crop_name", req.crop_name) \
        .order("created_at", desc=True) \
        .limit(1).execute() if farm_ids else None

    if inv_resp and inv_resp.data:
        inv_id = inv_resp.data[0]["id"]
        inventory_row = sb.table("inventory").select("quantity").eq("id", inv_id).limit(1).execute()
        if quantity_kg is None and inventory_row.data:
            quantity_kg = inventory_row.data[0].get("quantity")
        status_resp = sb.table("inventory_statuses").select("*") \
            .eq("inventory_id", inv_id) \
            .order("created_at", desc=True) \
            .limit(1).execute()
        if status_resp.data:
            shelf_info = status_resp.data[0]
            shelf_life_days = shelf_info.get("estimated_shelf_life_days") or shelf_life_days
            sell_by = shelf_info.get("sell_by_date")
            if sell_by:
                shelf_life_expiry = sell_by

    if shelf_life_days and not shelf_life_expiry:
        from datetime import datetime, timedelta
        harvested = datetime.fromisoformat(req.harvested_date)
        shelf_life_expiry = harvested + timedelta(days=int(shelf_life_days))

    row = {
        "farmer_id": current_farmer["id"],
        "crop_name": req.crop_name,
        "shelf_life_days": shelf_life_days,
        "harvested_date": req.harvested_date,
        "expected_price": req.expected_price,
        "quantity_kg": quantity_kg,
        "remaining_quantity_kg": quantity_kg,
        "sold_quantity_kg": 0,
        "shelf_life_expiry": shelf_life_expiry.isoformat() if shelf_life_expiry else None,
    }
    resp = sb.table("demand_requests").insert(row).execute()
    demand_request = resp.data[0]

    # Candidates are listed for the farmer to choose from; the request stays
    # "open" until a match is confirmed or a vendor accepts.
    matches = [_strip(m) for m in await run_demand_matching(demand_request, sb)][:3]

    for match in matches:
        sb.table("rescue_matches").insert({
            "demand_request_id": demand_request["id"],
            "matched_buyer_info": match,
        }).execute()

    return CropMatchResponse(
        demand_request_id=demand_request["id"],
        matches=matches,
        status="open",
    )


@router.get("/requests")
async def list_requests(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("demand_requests").select("*") \
        .eq("farmer_id", current_farmer["id"]) \
        .order("created_at", desc=True).execute()

    requests = resp.data or []
    if not requests:
        return requests

    ids = [r["id"] for r in requests]
    matches = sb.table("rescue_matches").select("*") \
        .in_("demand_request_id", ids) \
        .order("matched_at", desc=True).execute()

    by_request: dict[str, list] = {}
    for m in matches.data or []:
        by_request.setdefault(m["demand_request_id"], []).append(m)

    for r in requests:
        r["matches"] = []
        for m in by_request.get(r["id"], []):
            if isinstance(m.get("matched_buyer_info"), dict):
                buyer_info = _strip(dict(m["matched_buyer_info"]))
                m["matched_buyer_info"] = _enrich_buyer_info(sb, buyer_info)
            r["matches"].append(m)
    return requests


@router.patch("/{request_id}/extend-shelf-life")
async def extend_shelf_life(
    request_id: str,
    req: ExtendShelfLifeRequest,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()

    existing = sb.table("demand_requests").select("*") \
        .eq("id", request_id).eq("farmer_id", current_farmer["id"]).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Request not found")

    dr = existing.data[0]
    from datetime import datetime, timedelta
    current_expiry = datetime.fromisoformat(dr["shelf_life_expiry"]) if dr["shelf_life_expiry"] else datetime.utcnow()
    new_expiry = current_expiry + timedelta(days=req.additional_days)

    sb.table("demand_requests").update({
        "shelf_life_expiry": new_expiry.isoformat(),
        "status": "open",
    }).eq("id", request_id).execute()

    sb.table("notifications").delete() \
        .eq("related_id", request_id).eq("type", "shelf_life_expiring").execute()

    matches = [_strip(m) for m in await run_demand_matching(dr, sb)][:3]
    for match in matches:
        sb.table("rescue_matches").insert({
            "demand_request_id": request_id,
            "matched_buyer_info": match,
        }).execute()

    return {"request_id": request_id, "new_expiry": new_expiry.isoformat(), "matches": matches}


@router.patch("/matches/{match_id}/confirm")
async def confirm_match(
    match_id: str,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()

    # Get the match
    match_resp = sb.table("rescue_matches").select("*, demand_requests!inner(farmer_id, crop_name)") \
        .eq("id", match_id).execute()
    if not match_resp.data:
        raise HTTPException(status_code=404, detail="Match not found")

    match = match_resp.data[0]
    demand_farmer_id = match.get("demand_requests", {}).get("farmer_id") if isinstance(match.get("demand_requests"), dict) else None

    # Fallback: fetch demand_request directly if join didn't work
    if not demand_farmer_id:
        dr_resp = sb.table("demand_requests").select("farmer_id, crop_name") \
            .eq("id", match["demand_request_id"]).execute()
        if not dr_resp.data:
            raise HTTPException(status_code=404, detail="Demand request not found")
        demand_farmer_id = dr_resp.data[0]["farmer_id"]
        match["demand_requests"] = dr_resp.data[0]

    if demand_farmer_id != current_farmer["id"]:
        raise HTTPException(status_code=403, detail="Not authorized to confirm this match")

    if match.get("status") == "confirmed":
        return {"status": "confirmed", "match_id": match_id}

    from datetime import datetime
    sb.table("rescue_matches").update({
        "status": "confirmed",
        "confirmed_at": datetime.utcnow().isoformat(),
    }).eq("id", match_id).execute()

    # A partial sale leaves the parent request open for the remaining stock.
    demand_state = sb.table("demand_requests").select("remaining_quantity_kg") \
        .eq("id", match["demand_request_id"]).limit(1).execute()
    remaining = demand_state.data[0].get("remaining_quantity_kg") if demand_state.data else 0
    sb.table("demand_requests").update({
        "status": "matched" if remaining is not None and float(remaining) <= 0 else "open",
    }).eq("id", match["demand_request_id"]).execute()

    # Only close competing matches when the entire listing has been sold.
    if remaining is not None and float(remaining) <= 0:
        sb.table("rescue_matches").update({"status": "rejected"}) \
            .eq("demand_request_id", match["demand_request_id"]) \
            .neq("id", match_id).execute()

    crop_name = (
        match.get("demand_requests", {}).get("crop_name")
        if isinstance(match.get("demand_requests"), dict)
        else None
    )
    quantity = _as_float(match.get("quantity_kg"))
    if crop_name and quantity > 0:
        _reduce_inventory_for_sale(sb, current_farmer["id"], crop_name, quantity)

    # Notify counter-party if buyer info has an identifier
    buyer_info = match.get("matched_buyer_info", {})
    if buyer_info.get("buyer_farmer_id"):
        await create_notification(
            sb, buyer_info["buyer_farmer_id"], "sale_confirmed",
            "Sale Confirmed",
            f"Your purchase has been confirmed",
            match_id,
        )

    return {"status": "confirmed", "match_id": match_id}
