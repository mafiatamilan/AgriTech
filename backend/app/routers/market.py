from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.models.market import DemandRequestCreate, CropMatchResponse
from app.agents.demand_matching import run_demand_matching

router = APIRouter(prefix="/market", tags=["market"])


class ExtendShelfLifeRequest(BaseModel):
    additional_days: int


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

    matches = await run_demand_matching(demand_request)

    if matches:
        sb.table("demand_requests").update({"status": "matched"}) \
            .eq("id", demand_request["id"]).execute()
        for match in matches:
            sb.table("rescue_matches").insert({
                "demand_request_id": demand_request["id"],
                "matched_buyer_info": match,
            }).execute()

    return CropMatchResponse(
        demand_request_id=demand_request["id"],
        matches=matches,
        status="matched" if matches else "open",
    )


@router.get("/requests")
async def list_requests(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("demand_requests").select("*") \
        .eq("farmer_id", current_farmer["id"]) \
        .order("created_at", desc=True).execute()
    return resp.data


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
        .eq("related_id", request_id).eq("type", "match").execute()

    matches = await run_demand_matching(dr)
    if matches:
        sb.table("demand_requests").update({"status": "matched"}) \
            .eq("id", request_id).execute()
        for match in matches:
            sb.table("rescue_matches").insert({
                "demand_request_id": request_id,
                "matched_buyer_info": match,
            }).execute()

    return {"request_id": request_id, "new_expiry": new_expiry.isoformat(), "matches": matches}
