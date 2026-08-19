from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field
from datetime import datetime
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.services.notification_service import create_notification
from app.agents.transport_routing import (
    TransportOrder,
    VehicleProfile,
    recommend_transport_routes,
)

router = APIRouter(prefix="/vendors", tags=["vendors"])


def _as_float(value) -> float:
    if value is None:
        return 0.0
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


class VendorSignupRequest(BaseModel):
    name: str | None = None
    phone: str | None = None
    email: str | None = None
    business_name: str | None = None


class VendorRequestCreate(BaseModel):
    crop_name: str
    quantity_needed: float | None = None
    expected_price: float | None = None


class VendorAcceptRequest(BaseModel):
    quantity_kg: float


class TransportRouteRequest(BaseModel):
    pickup_location: dict
    delivery_location: dict
    quantity_kg: float | None = None
    vehicle_type: str = "small_truck"
    vehicle_capacity_kg: float = 1000.0
    transport_cost_per_km: float = 15.0
    refrigerated: bool = False
    harvest_time: datetime | None = None
    required_delivery_time: datetime | None = None
    shelf_life_hours: float | None = None
    current_weather: dict = Field(default_factory=dict)
    route_candidates: list[dict] = Field(default_factory=list)


@router.post("/signup")
async def vendor_signup(req: VendorSignupRequest | None = None, current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    req = req or VendorSignupRequest()
    resp = sb.table("vendors").select("id").eq("id", current_farmer["id"]).execute()
    if resp.data:
        raise HTTPException(status_code=409, detail="Vendor profile already exists")

    name = req.name or current_farmer.get("email") or "Vendor"
    sb.table("vendors").insert({
        "id": current_farmer["id"],
        "business_name": req.business_name or name,
        "contact_email": req.email,
        "contact_phone": req.phone,
    }).execute()

    return {"status": "created", "vendor_id": current_farmer["id"]}


@router.post("/requests")
async def create_vendor_request(
    req: VendorRequestCreate,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()

    # Verify caller is a vendor
    vendor = sb.table("vendors").select("id").eq("id", current_farmer["id"]).execute()
    if not vendor.data:
        raise HTTPException(status_code=403, detail="Not a registered vendor")

    resp = sb.table("vendor_requests").insert({
        "vendor_id": current_farmer["id"],
        "crop_name": req.crop_name,
        "quantity_needed": req.quantity_needed,
        "expected_price": req.expected_price,
    }).execute()

    return resp.data[0] if resp.data else {"status": "created"}


@router.get("/requests")
async def list_vendor_requests(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    vendor = sb.table("vendors").select("id").eq("id", current_farmer["id"]).execute()
    if not vendor.data:
        raise HTTPException(status_code=403, detail="Not a registered vendor")

    resp = sb.table("vendor_requests").select("*") \
        .eq("vendor_id", current_farmer["id"]) \
        .order("created_at", desc=True).execute()
    return resp.data


@router.get("/opportunities")
async def list_opportunities(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()

    vendor = sb.table("vendors").select("id").eq("id", current_farmer["id"]).execute()
    if not vendor.data:
        raise HTTPException(status_code=403, detail="Not a registered vendor")

    resp = sb.table("demand_requests").select("*") \
        .eq("status", "open") \
        .order("created_at", desc=True).execute()

    requests = resp.data or []
    if not requests:
        return []

    ids = [r["id"] for r in requests]
    bids = sb.table("rescue_matches").select("demand_request_id") \
        .in_("demand_request_id", ids) \
        .filter("matched_buyer_info->>buyer_farmer_id", "eq", current_farmer["id"]) \
        .execute()
    bid_ids = {b["demand_request_id"] for b in bids.data or []}

    visible_requests = []
    for request in requests:
        available = (
            request.get("remaining_quantity_kg")
            if request.get("remaining_quantity_kg") is not None
            else request.get("quantity_kg")
        )
        if (
            request["id"] not in bid_ids
            and request.get("farmer_id") != current_farmer["id"]
            and (request.get("crop_name") or "").strip()
            and _as_float(available) > 0
        ):
            visible_requests.append(request)
    return visible_requests


@router.post("/opportunities/{request_id}/route")
async def recommend_opportunity_route(
    request_id: str,
    req: TransportRouteRequest,
    current_farmer: dict = Depends(get_current_farmer),
):
    """Plan delivery after a vendor selects a farmer's crop opportunity.

    Route candidates are optional. With no external routing provider, the
    agent estimates distance from coordinates and travel time from average
    road speed. Maps/OSRM/Mapbox can later populate route_candidates.
    """
    sb = get_supabase()
    vendor = sb.table("vendors").select("id").eq("id", current_farmer["id"]).execute()
    if not vendor.data:
        raise HTTPException(status_code=403, detail="Not a registered vendor")

    dr = sb.table("demand_requests").select("*").eq("id", request_id).execute()
    if not dr.data:
        raise HTTPException(status_code=404, detail="Crop not found")
    demand = dr.data[0]

    order = TransportOrder(
        pickup_location=req.pickup_location,
        delivery_location=req.delivery_location,
        crop=demand.get("crop_name", "unknown"),
        quantity_kg=float(req.quantity_kg if req.quantity_kg is not None else (demand.get("quantity_kg") or demand.get("quantity") or 0)),
        harvest_time=req.harvest_time,
        required_delivery_time=req.required_delivery_time,
        vehicle=VehicleProfile(
            vehicle_type=req.vehicle_type,
            capacity_kg=req.vehicle_capacity_kg,
            cost_per_km=req.transport_cost_per_km,
            refrigerated=req.refrigerated,
        ),
        current_weather=req.current_weather,
        route_candidates=req.route_candidates,
        shelf_life_hours=req.shelf_life_hours,
    )
    recommendation = recommend_transport_routes(order)
    return {
        "request_id": request_id,
        "crop": order.crop,
        "quantity_kg": order.quantity_kg,
        "best_route": recommendation.best_route,
        "route_options": recommendation.route_options,
        "estimated_distance_km": recommendation.estimated_distance_km,
        "estimated_duration_minutes": recommendation.estimated_duration_minutes,
        "estimated_transport_cost": recommendation.estimated_transport_cost,
        "spoilage_risk": recommendation.spoilage_risk,
        "delay_risk": recommendation.delay_risk,
        "reason_labels": recommendation.reason_labels,
    }


@router.post("/opportunities/{request_id}/accept")
async def accept_opportunity(
    request_id: str,
    req: VendorAcceptRequest,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()

    vendor = sb.table("vendors").select("business_name").eq("id", current_farmer["id"]).execute()
    if not vendor.data:
        raise HTTPException(status_code=403, detail="Not a registered vendor")

    dr = sb.table("demand_requests").select("*").eq("id", request_id).execute()
    if not dr.data:
        raise HTTPException(status_code=404, detail="Crop not found")

    quantity = float(req.quantity_kg)
    if quantity <= 0:
        raise HTTPException(status_code=422, detail="quantity_kg must be greater than zero")
    available = dr.data[0].get("remaining_quantity_kg")
    if available is not None and quantity > float(available):
        raise HTTPException(status_code=409, detail=f"Only {available} kg remains available")

    existing = sb.table("rescue_matches").select("id, status") \
        .eq("demand_request_id", request_id) \
        .filter("matched_buyer_info->>buyer_farmer_id", "eq", current_farmer["id"]) \
        .execute()
    if existing.data:
        return {"status": existing.data[0]["status"], "match_id": existing.data[0]["id"]}

    buyer_info = {
        "buyer_name": vendor.data[0].get("business_name") or "Vendor",
        "buyer_farmer_id": current_farmer["id"],
        "offered_price": dr.data[0].get("expected_price"),
        "distance_km": None,
        "shelf_life_compatible": True,
    }
    try:
        reserved = sb.rpc("reserve_marketplace_quantity", {
            "p_demand_request_id": request_id,
            "p_vendor_id": current_farmer["id"],
            "p_quantity_kg": quantity,
            "p_buyer_info": buyer_info,
        }).execute()
    except Exception as exc:
        raise HTTPException(status_code=409, detail="Unable to reserve that quantity") from exc

    reservation = reserved.data if isinstance(reserved.data, dict) else {}

    await create_notification(
        sb,
        dr.data[0]["farmer_id"],
        "match",
        "New buyer match",
        f"{buyer_info['buyer_name']} wants {quantity:g} kg of your {dr.data[0]['crop_name']}",
        request_id,
    )

    return {
        "status": "proposed",
        "match_id": reservation.get("match_id"),
        "quantity_kg": quantity,
        "remaining_quantity_kg": reservation.get("remaining_quantity_kg"),
    }
