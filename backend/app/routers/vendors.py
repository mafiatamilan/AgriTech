from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from datetime import datetime
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase

router = APIRouter(prefix="/vendors", tags=["vendors"])


class VendorSignupRequest(BaseModel):
    name: str | None = None
    phone: str | None = None
    email: str | None = None
    business_name: str | None = None


class VendorRequestCreate(BaseModel):
    crop_name: str
    quantity_needed: float | None = None
    expected_price: float | None = None


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
    resp = sb.table("vendor_requests").select("*") \
        .eq("vendor_id", current_farmer["id"]) \
        .order("created_at", desc=True).execute()
    return resp.data
