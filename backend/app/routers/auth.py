from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from app.core.deps import get_current_farmer
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


@router.get("/me", response_model=FarmerProfile)
async def get_me(current_farmer: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    resp = sb.table("farmers").select("*").eq("id", current_farmer["id"]).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Farmer profile not found")
    return resp.data[0]
