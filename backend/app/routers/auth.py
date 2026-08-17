from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from app.core.deps import get_current_farmer
from app.core.security import decode_jwt
from app.db.supabase_client import get_supabase

router = APIRouter(prefix="/auth", tags=["auth"])


class SignupRequest(BaseModel):
    email: str
    password: str
    name: str
    phone: str | None = None


class LoginRequest(BaseModel):
    email: str
    password: str


class AuthResponse(BaseModel):
    access_token: str
    user_id: str


class FarmerProfile(BaseModel):
    id: str
    name: str
    phone: str | None = None
    email: str | None = None
    preferred_language: str = "en"
    soil_type: str | None = None
    area_locality: str | None = None


class OAuthExchangeRequest(BaseModel):
    access_token: str


class OAuthExchangeResponse(BaseModel):
    profile: FarmerProfile
    is_new_user: bool


@router.post("/signup", response_model=AuthResponse)
async def signup(req: SignupRequest):
    sb = get_supabase()
    try:
        resp = sb.auth.sign_up({"email": req.email, "password": req.password})
        if not resp.user:
            raise HTTPException(status_code=400, detail="Signup failed")
        sb.table("farmers").insert({
            "id": resp.user.id,
            "name": req.name,
            "phone": req.phone,
            "email": req.email,
        }).execute()
        return AuthResponse(access_token=resp.session.access_token, user_id=resp.user.id)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/login", response_model=AuthResponse)
async def login(req: LoginRequest):
    sb = get_supabase()
    try:
        resp = sb.auth.sign_in_with_password({"email": req.email, "password": req.password})
        if not resp.session:
            raise HTTPException(status_code=401, detail="Invalid credentials")
        return AuthResponse(access_token=resp.session.access_token, user_id=resp.user.id)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=401, detail=str(e))


@router.post("/oauth/exchange", response_model=OAuthExchangeResponse)
async def oauth_exchange(req: OAuthExchangeRequest):
    payload = decode_jwt(req.access_token)
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid token: no sub claim")

    sb = get_supabase()

    # Check if farmer already exists
    existing = sb.table("farmers").select("*").eq("id", user_id).execute()
    if existing.data:
        return OAuthExchangeResponse(
            profile=FarmerProfile(**existing.data[0]),
            is_new_user=False,
        )

    # Fetch user info from Supabase Auth
    try:
        user_resp = sb.auth.get_user(req.access_token)
        user = user_resp.user if user_resp else None
    except Exception:
        user = None

    name = ""
    email = ""
    if user:
        name = user.user_metadata.get("full_name", "") or user.user_metadata.get("name", "") or ""
        email = user.email or ""

    sb.table("farmers").insert({
        "id": user_id,
        "name": name,
        "email": email,
    }).execute()

    profile = FarmerProfile(id=user_id, name=name, email=email)
    return OAuthExchangeResponse(profile=profile, is_new_user=True)


@router.get("/me", response_model=FarmerProfile)
async def get_me(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("farmers").select("*").eq("id", current_farmer["id"]).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Farmer profile not found")
    return resp.data[0]
