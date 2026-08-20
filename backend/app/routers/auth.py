from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.models.verification import SignupStartRequest, SignupStartResponse, UserRole, VerificationStatus
from app.services.identity_verification_service import ensure_user_profile, is_demo_mode

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
    refresh_token: str
    user_id: str


class FarmerProfile(BaseModel):
    id: str
    name: str
    phone: str | None = None
    email: str | None = None
    preferred_language: str = "en"
    soil_type: str | None = None
    area_locality: str | None = None
    role: str | None = None
    state: str | None = None
    district: str | None = None
    verification_status: str = "UNVERIFIED"
    verification_badge: str | None = None
    demo_verification_mode: bool = False


def _find_user_by_email(sb, email: str):
    users = sb.auth.admin.list_users()
    user_list = getattr(users, "users", users)
    for user in user_list:
        if getattr(user, "email", None) == email:
            return user
    return None


@router.post("/signup", response_model=AuthResponse)
async def signup(req: SignupRequest):
    sb = get_supabase()
    try:
        try:
            resp = sb.auth.admin.create_user({
                "email": req.email,
                "password": req.password,
                "email_confirm": True,
            })
            user = resp.user
        except Exception:
            existing_user = _find_user_by_email(sb, req.email)
            if not existing_user:
                raise
            sb.auth.admin.update_user_by_id(existing_user.id, {
                "password": req.password,
                "email_confirm": True,
            })
            user = existing_user
        if not user:
            raise HTTPException(status_code=400, detail="Signup failed")
        sb.table("farmers").upsert({
            "id": user.id,
            "name": req.name,
            "phone": req.phone,
            "email": req.email,
        }).execute()
        ensure_user_profile(
            sb,
            auth_user_id=user.id,
            role=UserRole.farmer,
            full_name=req.name,
            phone=req.phone or "",
            state="",
            district="",
        )
        login_resp = sb.auth.sign_in_with_password({"email": req.email, "password": req.password})
        if not login_resp.session:
            raise HTTPException(status_code=401, detail="Signup created user, but login failed")
        return AuthResponse(
            access_token=login_resp.session.access_token,
            refresh_token=login_resp.session.refresh_token,
            user_id=user.id,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/signup/start", response_model=SignupStartResponse)
async def signup_start(req: SignupStartRequest):
    if not req.consent:
        raise HTTPException(status_code=422, detail="Consent is required to start identity verification")
    sb = get_supabase()
    try:
        try:
            resp = sb.auth.admin.create_user({
                "email": req.email,
                "password": req.password,
                "email_confirm": True,
                "phone": req.phone,
            })
            user = resp.user
        except Exception:
            existing_user = _find_user_by_email(sb, req.email)
            if not existing_user:
                raise
            sb.auth.admin.update_user_by_id(existing_user.id, {
                "password": req.password,
                "email_confirm": True,
                "phone": req.phone,
            })
            user = existing_user
        if not user:
            raise HTTPException(status_code=400, detail="Signup failed")

        ensure_user_profile(
            sb,
            auth_user_id=user.id,
            role=req.role,
            full_name=req.full_name,
            phone=req.phone,
            state=req.state,
            district=req.district,
        )
        if req.role == UserRole.farmer:
            sb.table("farmers").upsert({
                "id": user.id,
                "name": req.full_name or req.email,
                "phone": req.phone,
                "email": req.email,
            }).execute()
        elif req.role == UserRole.vendor:
            sb.table("vendors").upsert({
                "id": user.id,
                "business_name": req.full_name or req.email,
                "contact_phone": req.phone,
                "contact_email": req.email,
            }).execute()

        login_resp = sb.auth.sign_in_with_password({"email": req.email, "password": req.password})
        if not login_resp.session:
            raise HTTPException(status_code=401, detail="Signup created user, but login failed")
        return SignupStartResponse(
            access_token=login_resp.session.access_token,
            refresh_token=login_resp.session.refresh_token,
            user_id=user.id,
            role=req.role,
            verification_status=VerificationStatus.unverified,
            demo_mode=is_demo_mode(),
        )
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
        return AuthResponse(
            access_token=resp.session.access_token,
            refresh_token=resp.session.refresh_token,
            user_id=resp.user.id,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=401, detail=str(e))


@router.get("/me", response_model=FarmerProfile)
async def get_me(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("farmers").select("*").eq("id", current_farmer["id"]).execute()
    profile = resp.data[0] if resp.data else {
        "id": current_farmer["id"],
        "name": current_farmer.get("email") or "",
        "email": current_farmer.get("email"),
    }
    verification = sb.table("user_profiles").select("*") \
        .eq("auth_user_id", current_farmer["id"]).limit(1).execute()
    if verification.data:
        row = verification.data[0]
        profile["role"] = row.get("role")
        profile["state"] = row.get("state")
        profile["district"] = row.get("district")
        profile["verification_status"] = row.get("verification_status") or "UNVERIFIED"
        if row.get("verification_status") == "IDENTITY_VERIFIED":
            profile["verification_badge"] = "VERIFIED_VENDOR" if row.get("role") == "VENDOR" else "VERIFIED_FARMER"
        profile["demo_verification_mode"] = is_demo_mode()
    return profile
