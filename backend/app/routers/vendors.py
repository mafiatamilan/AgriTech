from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field
from datetime import datetime
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.models.verification import UserRole
from app.services.identity_verification_service import require_verified_role
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


def _attach_farmer_profiles(sb, requests: list[dict]) -> list[dict]:
    farmer_ids = list({request.get("farmer_id") for request in requests if request.get("farmer_id")})
    if not farmer_ids:
        return requests
    farmers = sb.table("farmers").select("id, name, phone, email, area_locality") \
        .in_("id", farmer_ids).execute()
    by_farmer = {farmer["id"]: farmer for farmer in farmers.data or []}
    for request in requests:
        farmer = by_farmer.get(request.get("farmer_id"))
        if farmer:
            request["farmer_profile"] = {
                "id": farmer.get("id"),
                "name": farmer.get("name"),
                "phone": farmer.get("phone"),
                "email": farmer.get("email"),
                "address": farmer.get("area_locality"),
            }
    return requests


class VendorSignupRequest(BaseModel):
    name: str | None = None
    phone: str | None = None
    email: str | None = None
    business_name: str | None = None
    address: str | None = None


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


class TransportCropItem(BaseModel):
    crop_name: str
    quantity_kg: float
    pickup_location: dict | None = None
    shelf_life_hours: float | None = None
    harvest_time: datetime | None = None


class VendorTransportPlanRequest(BaseModel):
    delivery_day: datetime
    delivery_location: dict
    vehicle_type: str = "small_truck"
    vehicle_capacity_kg: float = 1000.0
    transport_cost_per_km: float = 15.0
    refrigerated: bool = False
    confirmed_match_ids: list[str] = Field(default_factory=list)
    crop_items: list[TransportCropItem] = Field(default_factory=list)
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
        "address": req.address,
    }).execute()

    return {"status": "created", "vendor_id": current_farmer["id"]}


@router.post("/requests")
async def create_vendor_request(
    req: VendorRequestCreate,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    require_verified_role(sb, user_id=current_farmer["id"], role=UserRole.vendor)

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

    request_row = resp.data[0] if resp.data else None
    if request_row:
        listings = sb.table("demand_requests").select("*") \
            .eq("crop_name", req.crop_name) \
            .eq("status", "open") \
            .execute()
        profile_resp = sb.table("vendors").select("business_name, contact_phone, contact_email, address") \
            .eq("id", current_farmer["id"]).limit(1).execute()
        profile = profile_resp.data[0] if profile_resp.data else {}

        for listing in listings.data or []:
            available = (
                listing.get("remaining_quantity_kg")
                if listing.get("remaining_quantity_kg") is not None
                else listing.get("quantity_kg")
            )
            if _as_float(available) <= 0:
                continue
            exists = sb.table("rescue_matches").select("id") \
                .eq("demand_request_id", listing["id"]) \
                .filter("matched_buyer_info->>buyer_farmer_id", "eq", current_farmer["id"]) \
                .limit(1).execute()
            if exists.data:
                continue
            buyer_info = {
                "buyer_name": profile.get("business_name") or "Vendor",
                "buyer_farmer_id": current_farmer["id"],
                "buyer_phone": profile.get("contact_phone"),
                "buyer_email": profile.get("contact_email"),
                "buyer_address": profile.get("address"),
                "offered_price": req.expected_price,
                "distance_km": None,
                "shelf_life_compatible": True,
                "reason": "Vendor request matches this crop",
            }
            sb.table("rescue_matches").insert({
                "demand_request_id": listing["id"],
                "vendor_request_id": request_row["id"],
                "matched_buyer_info": buyer_info,
                "quantity_kg": min(_as_float(req.quantity_needed), _as_float(available)) if req.quantity_needed else _as_float(available),
                "status": "proposed",
            }).execute()
            await create_notification(
                sb,
                listing["farmer_id"],
                "match",
                "New vendor request",
                f"{buyer_info['buyer_name']} is looking for {req.crop_name}",
                listing["id"],
            )

    return request_row if request_row else {"status": "created"}


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


@router.get("/kpis")
async def vendor_kpis(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    vendor = sb.table("vendors").select("id").eq("id", current_farmer["id"]).execute()
    if not vendor.data:
        raise HTTPException(status_code=403, detail="Not a registered vendor")

    requests = sb.table("vendor_requests").select("*") \
        .eq("vendor_id", current_farmer["id"]).execute()
    matches = sb.table("rescue_matches").select("*") \
        .filter("matched_buyer_info->>buyer_farmer_id", "eq", current_farmer["id"]) \
        .execute()

    request_rows = requests.data or []
    match_rows = matches.data or []
    confirmed = [m for m in match_rows if m.get("status") == "confirmed"]
    proposed = [m for m in match_rows if m.get("status") == "proposed"]
    confirmed_qty = sum(_as_float(m.get("quantity_kg")) for m in confirmed)
    committed_value = 0.0
    for match in confirmed:
        info = match.get("matched_buyer_info") if isinstance(match.get("matched_buyer_info"), dict) else {}
        committed_value += _as_float(match.get("quantity_kg")) * _as_float(info.get("offered_price"))

    return {
        "items": [
            {
                "key": "open_requests",
                "label": "Open requests",
                "value": len([r for r in request_rows if r.get("status") == "open"]),
                "unit": "requests",
                "formula": "count(vendor_requests where status = open)",
                "parameters": ["vendor_id", "vendor_requests.status"],
            },
            {
                "key": "proposed_matches",
                "label": "Waiting farmer confirmation",
                "value": len(proposed),
                "unit": "matches",
                "formula": "count(rescue_matches where status = proposed and buyer_farmer_id = vendor_id)",
                "parameters": ["vendor_id", "rescue_matches.status", "matched_buyer_info.buyer_farmer_id"],
            },
            {
                "key": "confirmed_quantity_kg",
                "label": "Confirmed volume",
                "value": round(confirmed_qty, 2),
                "unit": "kg",
                "formula": "sum(confirmed rescue_matches.quantity_kg)",
                "parameters": ["vendor_id", "rescue_matches.quantity_kg", "rescue_matches.status"],
            },
            {
                "key": "committed_value",
                "label": "Committed value",
                "value": round(committed_value, 2),
                "unit": "INR",
                "formula": "sum(quantity_kg * offered_price)",
                "parameters": ["rescue_matches.quantity_kg", "matched_buyer_info.offered_price"],
            },
        ]
    }


@router.get("/confirmed-sales")
async def confirmed_sales(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    vendor = sb.table("vendors").select("id").eq("id", current_farmer["id"]).execute()
    if not vendor.data:
        raise HTTPException(status_code=403, detail="Not a registered vendor")

    resp = sb.table("rescue_matches").select("*, demand_requests(*)") \
        .eq("status", "confirmed") \
        .filter("matched_buyer_info->>buyer_farmer_id", "eq", current_farmer["id"]) \
        .order("confirmed_at", desc=True).execute()
    rows = []
    farmer_ids = set()
    for match in resp.data or []:
        demand = match.get("demand_requests") if isinstance(match.get("demand_requests"), dict) else {}
        if demand.get("farmer_id"):
            farmer_ids.add(demand["farmer_id"])
        rows.append({"match": match, "demand_request": demand})

    profiles = {}
    if farmer_ids:
        farmer_resp = sb.table("farmers").select("id, name, phone, email, area_locality") \
            .in_("id", list(farmer_ids)).execute()
        profiles = {row["id"]: row for row in farmer_resp.data or []}
    for row in rows:
        farmer = profiles.get(row["demand_request"].get("farmer_id"))
        if farmer:
            row["farmer_profile"] = {
                "id": farmer.get("id"),
                "name": farmer.get("name"),
                "phone": farmer.get("phone"),
                "email": farmer.get("email"),
                "address": farmer.get("area_locality"),
            }
    return rows


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
    return _attach_farmer_profiles(sb, visible_requests)


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


@router.post("/transport/route")
async def recommend_vendor_transport_route(
    req: VendorTransportPlanRequest,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    vendor = sb.table("vendors").select("id").eq("id", current_farmer["id"]).execute()
    if not vendor.data:
        raise HTTPException(status_code=403, detail="Not a registered vendor")

    items: list[TransportCropItem] = list(req.crop_items)
    if req.confirmed_match_ids:
        matches = sb.table("rescue_matches").select("*, demand_requests(*)") \
            .in_("id", req.confirmed_match_ids) \
            .eq("status", "confirmed") \
            .filter("matched_buyer_info->>buyer_farmer_id", "eq", current_farmer["id"]) \
            .execute()
        for match in matches.data or []:
            demand = match.get("demand_requests") if isinstance(match.get("demand_requests"), dict) else {}
            shelf_hours = None
            if demand.get("shelf_life_days") is not None:
                shelf_hours = float(demand["shelf_life_days"]) * 24
            items.append(TransportCropItem(
                crop_name=demand.get("crop_name") or "crop",
                quantity_kg=_as_float(match.get("quantity_kg")),
                pickup_location={
                    "latitude": demand.get("latitude"),
                    "longitude": demand.get("longitude"),
                    "address": demand.get("location"),
                },
                shelf_life_hours=shelf_hours,
                harvest_time=datetime.fromisoformat(str(demand["harvested_date"])) if demand.get("harvested_date") else None,
            ))

    if not items:
        raise HTTPException(status_code=422, detail="Add at least one crop or confirmed sale")

    primary = max(items, key=lambda item: item.quantity_kg)
    pickup = primary.pickup_location or {}
    if pickup.get("latitude") is None or pickup.get("longitude") is None:
        raise HTTPException(status_code=422, detail="Pickup latitude and longitude are required")

    total_quantity = sum(item.quantity_kg for item in items)
    shelf_life_hours = min(
        [item.shelf_life_hours for item in items if item.shelf_life_hours is not None],
        default=None,
    )
    harvest_times = [item.harvest_time for item in items if item.harvest_time is not None]
    harvest_time = min(harvest_times) if harvest_times else None

    order = TransportOrder(
        pickup_location=pickup,
        delivery_location=req.delivery_location,
        crop=", ".join(item.crop_name for item in items),
        quantity_kg=total_quantity,
        harvest_time=harvest_time,
        required_delivery_time=req.delivery_day,
        vehicle=VehicleProfile(
            vehicle_type=req.vehicle_type,
            capacity_kg=req.vehicle_capacity_kg,
            cost_per_km=req.transport_cost_per_km,
            refrigerated=req.refrigerated,
        ),
        current_weather=req.current_weather,
        route_candidates=req.route_candidates,
        shelf_life_hours=shelf_life_hours,
    )
    recommendation = recommend_transport_routes(order)
    return {
        "delivery_day": req.delivery_day.isoformat(),
        "crops": [item.model_dump(mode="json") for item in items],
        "vehicle": order.vehicle.__dict__,
        "quantity_kg": total_quantity,
        "best_route": recommendation.best_route,
        "route_options": recommendation.route_options,
        "estimated_distance_km": recommendation.estimated_distance_km,
        "estimated_duration_minutes": recommendation.estimated_duration_minutes,
        "estimated_transport_cost": recommendation.estimated_transport_cost,
        "spoilage_risk": recommendation.spoilage_risk,
        "delay_risk": recommendation.delay_risk,
        "reason_labels": recommendation.reason_labels,
        "calculation_matrix": {
            "distance_km": "haversine pickup-to-delivery distance * 1.2 road factor, unless route_candidates override it",
            "duration_hours": "route candidate duration, otherwise distance_km / 35",
            "transport_cost": "distance_km * vehicle_cost_per_km",
            "capacity_fit": "total_quantity_kg <= vehicle_capacity_kg",
            "spoilage_risk": "crop damage risk + duration / crop max transport hours + capacity penalty",
            "delay_risk": "duration / crop max transport hours + weather risk + capacity penalty",
        },
    }


@router.post("/opportunities/{request_id}/accept")
async def accept_opportunity(
    request_id: str,
    req: VendorAcceptRequest,
    current_farmer: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    require_verified_role(sb, user_id=current_farmer["id"], role=UserRole.vendor)

    vendor = sb.table("vendors") \
        .select("business_name, contact_phone, contact_email, address") \
        .eq("id", current_farmer["id"]).execute()
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
        "buyer_phone": vendor.data[0].get("contact_phone"),
        "buyer_email": vendor.data[0].get("contact_email"),
        "buyer_address": vendor.data[0].get("address"),
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
