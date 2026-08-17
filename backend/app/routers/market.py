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

    shelf_life_expiry = None
    if req.shelf_life_days:
        from datetime import datetime, timedelta
        harvested = datetime.fromisoformat(req.harvested_date)
        shelf_life_expiry = harvested + timedelta(days=req.shelf_life_days)

    row = {
        "farmer_id": current_farmer["id"],
        "crop_name": req.crop_name,
        "shelf_life_days": req.shelf_life_days,
        "harvested_date": req.harvested_date,
        "expected_price": req.expected_price,
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
                m["matched_buyer_info"] = _strip(dict(m["matched_buyer_info"]))
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

    if demand_farmer_id != current_farmer["id"]:
        raise HTTPException(status_code=403, detail="Not authorized to confirm this match")

    from datetime import datetime
    sb.table("rescue_matches").update({
        "status": "confirmed",
        "confirmed_at": datetime.utcnow().isoformat(),
    }).eq("id", match_id).execute()

    # Mark parent request as matched
    sb.table("demand_requests").update({"status": "matched"}) \
        .eq("id", match["demand_request_id"]).execute()

    # Reject/expire other matches for same request
    sb.table("rescue_matches").update({"status": "rejected"}) \
        .eq("demand_request_id", match["demand_request_id"]) \
        .neq("id", match_id).execute()

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
