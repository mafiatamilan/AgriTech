import hashlib
import hmac
import secrets
import time
from datetime import datetime, timedelta, UTC
from fastapi import HTTPException
from app.core.config import get_settings
from app.models.verification import VerificationStatus, UserRole, VerificationType
from app.services.identity_providers import (
    get_aadhaar_provider,
    get_farmer_identity_provider,
    get_vendor_identity_provider,
)


_rate_bucket: dict[tuple[str, str], list[float]] = {}


def is_demo_mode() -> bool:
    return get_settings().IDENTITY_PROVIDER_MODE == "mock"


def mask_identifier(value: str, keep: int = 4) -> str:
    cleaned = "".join(ch for ch in value if ch.isalnum())
    if len(cleaned) <= keep:
        return "*" * len(cleaned)
    return f"{'*' * (len(cleaned) - keep)}{cleaned[-keep:]}"


def mask_aadhaar(value: str) -> str:
    return f"XXXX XXXX {value[-4:]}"


def verification_badge(role: str | None, status: str | None) -> str | None:
    if status != VerificationStatus.identity_verified:
        return None
    if role == UserRole.farmer:
        return "VERIFIED_FARMER"
    if role == UserRole.vendor:
        return "VERIFIED_VENDOR"
    return None


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _hash_otp(otp: str, salt: str) -> str:
    secret = get_settings().SUPABASE_JWT_SECRET or "dev-verification-secret"
    payload = f"{salt}.{otp}".encode("utf-8")
    return hmac.new(secret.encode("utf-8"), payload, hashlib.sha256).hexdigest()


def _check_rate_limit(key: str, action: str) -> None:
    settings = get_settings()
    bucket_key = (key, action)
    now = time.time()
    window_start = now - 3600
    attempts = [ts for ts in _rate_bucket.get(bucket_key, []) if ts > window_start]
    if len(attempts) >= settings.OTP_RATE_LIMIT_PER_HOUR:
        raise HTTPException(status_code=429, detail="Too many verification attempts. Try again later.")
    attempts.append(now)
    _rate_bucket[bucket_key] = attempts


def _table_data(resp) -> list[dict]:
    return resp.data or []


def audit(sb, user_id: str, action: str, status: str, metadata: dict | None = None) -> None:
    safe_metadata = metadata or {}
    safe_metadata.pop("otp", None)
    safe_metadata.pop("aadhaar_number", None)
    sb.table("verification_audit_logs").insert({
        "user_id": user_id,
        "action": action,
        "status": status,
        "metadata": safe_metadata,
    }).execute()


def ensure_user_profile(
    sb,
    *,
    auth_user_id: str,
    role: UserRole,
    full_name: str | None,
    phone: str,
    state: str,
    district: str,
) -> dict:
    existing = sb.table("user_profiles").select("*").eq("auth_user_id", auth_user_id).limit(1).execute()
    row = {
        "auth_user_id": auth_user_id,
        "role": role,
        "full_name": full_name,
        "phone": phone,
        "state": state,
        "district": district,
        "verification_status": VerificationStatus.unverified,
    }
    if _table_data(existing):
        profile = _table_data(existing)[0]
        sb.table("user_profiles").update(row).eq("id", profile["id"]).execute()
        return {**profile, **row}
    created = sb.table("user_profiles").insert(row).execute()
    return _table_data(created)[0]


def get_profile_for_auth_user(sb, auth_user_id: str) -> dict | None:
    resp = sb.table("user_profiles").select("*").eq("auth_user_id", auth_user_id).limit(1).execute()
    rows = _table_data(resp)
    return rows[0] if rows else None


def set_status(sb, user_id: str, status: VerificationStatus) -> None:
    sb.table("user_profiles").update({"verification_status": status, "updated_at": _utc_now().isoformat()}).eq("auth_user_id", user_id).execute()


def send_phone_otp(sb, *, user_id: str, phone: str, purpose: str = "PHONE") -> str:
    _check_rate_limit(user_id, f"{purpose}:send")
    otp = get_settings().VERIFICATION_DEMO_OTP if is_demo_mode() else f"{secrets.randbelow(1000000):06d}"
    salt = secrets.token_hex(16)
    expires_at = _utc_now() + timedelta(seconds=get_settings().OTP_EXPIRY_SECONDS)
    sb.table("verification_otps").insert({
        "user_id": user_id,
        "purpose": purpose,
        "recipient": phone,
        "otp_hash": _hash_otp(otp, salt),
        "salt": salt,
        "expires_at": expires_at.isoformat(),
        "max_attempts": get_settings().OTP_MAX_ATTEMPTS,
    }).execute()
    audit(sb, user_id, f"{purpose}_OTP_SENT", "OTP_SENT", {"recipient": mask_identifier(phone), "demo_mode": is_demo_mode()})
    return otp


def verify_phone_otp(sb, *, user_id: str, phone: str, otp: str, purpose: str = "PHONE") -> bool:
    _check_rate_limit(user_id, f"{purpose}:verify")
    resp = sb.table("verification_otps").select("*") \
        .eq("user_id", user_id).eq("purpose", purpose).eq("recipient", phone) \
        .eq("consumed", False).order("created_at", desc=True).limit(1).execute()
    rows = _table_data(resp)
    if not rows:
        raise HTTPException(status_code=400, detail="OTP not found or already used")
    row = rows[0]
    if datetime.fromisoformat(str(row["expires_at"]).replace("Z", "+00:00")) < _utc_now():
        raise HTTPException(status_code=400, detail="OTP expired")
    attempts = int(row.get("attempt_count") or 0)
    if attempts >= int(row.get("max_attempts") or get_settings().OTP_MAX_ATTEMPTS):
        raise HTTPException(status_code=429, detail="OTP retry limit exceeded")
    expected = _hash_otp(otp, row["salt"])
    if not hmac.compare_digest(expected, row["otp_hash"]):
        sb.table("verification_otps").update({"attempt_count": attempts + 1}).eq("id", row["id"]).execute()
        audit(sb, user_id, f"{purpose}_OTP_FAILED", "FAILED", {"recipient": mask_identifier(phone)})
        raise HTTPException(status_code=400, detail="Invalid OTP")
    sb.table("verification_otps").update({"consumed": True, "consumed_at": _utc_now().isoformat()}).eq("id", row["id"]).execute()
    if purpose == "PHONE":
        set_status(sb, user_id, VerificationStatus.phone_verified)
    audit(sb, user_id, f"{purpose}_OTP_VERIFIED", "VERIFIED", {"recipient": mask_identifier(phone)})
    return True


async def start_farmer_verification(sb, *, user_id: str, req) -> dict:
    if not req.consent:
        raise HTTPException(status_code=422, detail="Consent is required for farmer identity verification")
    duplicate = sb.table("farmer_profiles").select("user_id").eq("farmer_id", req.farmer_id).neq("user_id", user_id).limit(1).execute()
    if _table_data(duplicate):
        raise HTTPException(status_code=409, detail="Farmer ID already linked to another account")
    provider = get_farmer_identity_provider()
    result = await provider.verify_farmer_id(
        farmer_id=req.farmer_id,
        mobile_number=req.mobile_number,
        state=req.state,
        district=req.district,
        full_name=req.full_name,
    )
    status = VerificationStatus.identity_pending if result.ok else VerificationStatus.identity_failed
    set_status(sb, user_id, status)
    profile = {
        "user_id": user_id,
        "farmer_id": req.farmer_id,
        "farmer_id_verified": False,
        "farmer_registry_state": req.state,
    }
    sb.table("farmer_profiles").upsert(profile).execute()
    verification = sb.table("identity_verifications").insert({
        "user_id": user_id,
        "verification_type": VerificationType.farmer_registry,
        "provider": get_settings().IDENTITY_PROVIDER_MODE,
        "external_reference": result.external_reference,
        "masked_identifier": mask_identifier(req.farmer_id),
        "status": status,
        "failure_reason": result.failure_reason,
        "consent_given_at": _utc_now().isoformat(),
        "metadata": {"state": req.state, "district": req.district, **result.metadata},
    }).execute()
    audit(sb, user_id, "FARMER_VERIFICATION_STARTED", status, {"farmer_id": mask_identifier(req.farmer_id), "demo_mode": is_demo_mode()})
    return _table_data(verification)[0]


async def send_farmer_otp(sb, *, user_id: str, farmer_id: str, mobile_number: str) -> None:
    result = await get_farmer_identity_provider().send_otp(farmer_id=farmer_id, mobile_number=mobile_number)
    if not result.ok:
        raise HTTPException(status_code=400, detail=result.failure_reason or "Unable to send farmer OTP")
    send_phone_otp(sb, user_id=user_id, phone=mobile_number, purpose="FARMER")


async def verify_farmer(sb, *, user_id: str, req) -> None:
    verify_phone_otp(sb, user_id=user_id, phone=req.mobile_number, otp=req.otp, purpose="FARMER")
    result = await get_farmer_identity_provider().verify_otp(farmer_id=req.farmer_id, mobile_number=req.mobile_number, otp=req.otp)
    if not result.ok:
        set_status(sb, user_id, VerificationStatus.identity_failed)
        raise HTTPException(status_code=400, detail=result.failure_reason or "Farmer verification failed")
    sb.table("farmer_profiles").update({"farmer_id_verified": True}).eq("user_id", user_id).eq("farmer_id", req.farmer_id).execute()
    sb.table("identity_verifications").update({
        "status": VerificationStatus.identity_verified,
        "verified_at": _utc_now().isoformat(),
        "external_reference": result.external_reference,
    }).eq("user_id", user_id).eq("verification_type", VerificationType.farmer_registry).execute()
    set_status(sb, user_id, VerificationStatus.identity_verified)
    audit(sb, user_id, "FARMER_VERIFIED", "VERIFIED", {"farmer_id": mask_identifier(req.farmer_id), "demo_mode": is_demo_mode()})


async def start_vendor_verification(sb, *, user_id: str, req) -> dict:
    if not req.consent:
        raise HTTPException(status_code=422, detail="Consent is required for vendor identity verification")
    duplicate = sb.table("vendor_profiles").select("user_id").eq("registration_number", req.registration_number).neq("user_id", user_id).limit(1).execute()
    if _table_data(duplicate):
        raise HTTPException(status_code=409, detail="Vendor registration already linked to another account")
    result = await get_vendor_identity_provider().verify_registration(
        verification_type=req.verification_type,
        registration_number=req.registration_number,
        mobile_number=req.mobile_number,
        state=req.state,
        district=req.district,
        business_name=req.business_name,
    )
    status = VerificationStatus.identity_pending if result.ok else VerificationStatus.identity_failed
    set_status(sb, user_id, status)
    sb.table("vendor_profiles").upsert({
        "user_id": user_id,
        "business_name": req.business_name,
        "contact_person": req.contact_person,
        "verification_type": req.verification_type,
        "registration_number": req.registration_number,
        "gstin": req.gstin,
        "vendor_verified": False,
    }).execute()
    verification = sb.table("identity_verifications").insert({
        "user_id": user_id,
        "verification_type": req.verification_type,
        "provider": get_settings().IDENTITY_PROVIDER_MODE,
        "external_reference": result.external_reference,
        "masked_identifier": mask_identifier(req.registration_number),
        "status": status,
        "failure_reason": result.failure_reason,
        "consent_given_at": _utc_now().isoformat(),
        "metadata": {"state": req.state, "district": req.district, "gstin_last4": req.gstin[-4:] if req.gstin else None, **result.metadata},
    }).execute()
    audit(sb, user_id, "VENDOR_VERIFICATION_STARTED", status, {"registration": mask_identifier(req.registration_number), "demo_mode": is_demo_mode()})
    return _table_data(verification)[0]


async def send_vendor_otp(sb, *, user_id: str, req) -> None:
    result = await get_vendor_identity_provider().send_otp(
        verification_type=req.verification_type,
        registration_number=req.registration_number,
        mobile_number=req.mobile_number,
    )
    if not result.ok:
        raise HTTPException(status_code=400, detail=result.failure_reason or "Unable to send vendor OTP")
    send_phone_otp(sb, user_id=user_id, phone=req.mobile_number, purpose="VENDOR")


async def verify_vendor(sb, *, user_id: str, req) -> None:
    verify_phone_otp(sb, user_id=user_id, phone=req.mobile_number, otp=req.otp, purpose="VENDOR")
    result = await get_vendor_identity_provider().verify_otp(
        verification_type=req.verification_type,
        registration_number=req.registration_number,
        mobile_number=req.mobile_number,
        otp=req.otp,
    )
    if not result.ok:
        set_status(sb, user_id, VerificationStatus.identity_failed)
        raise HTTPException(status_code=400, detail=result.failure_reason or "Vendor verification failed")
    sb.table("vendor_profiles").update({"vendor_verified": True}).eq("user_id", user_id).eq("registration_number", req.registration_number).execute()
    sb.table("identity_verifications").update({
        "status": VerificationStatus.identity_verified,
        "verified_at": _utc_now().isoformat(),
        "external_reference": result.external_reference,
    }).eq("user_id", user_id).eq("verification_type", req.verification_type).execute()
    set_status(sb, user_id, VerificationStatus.identity_verified)
    audit(sb, user_id, "VENDOR_VERIFIED", "VERIFIED", {"registration": mask_identifier(req.registration_number), "demo_mode": is_demo_mode()})


async def request_aadhaar_otp(sb, *, user_id: str, aadhaar_number: str, consent: bool) -> dict:
    if not consent:
        raise HTTPException(status_code=422, detail="Aadhaar consent is required")
    result = await get_aadhaar_provider().request_otp(aadhaar_number=aadhaar_number)
    if not result.ok:
        raise HTTPException(status_code=400, detail=result.failure_reason or "Unable to request Aadhaar OTP")
    send_phone_otp(sb, user_id=user_id, phone=aadhaar_number[-4:], purpose="AADHAAR")
    verification = sb.table("identity_verifications").insert({
        "user_id": user_id,
        "verification_type": VerificationType.aadhaar,
        "provider": get_settings().IDENTITY_PROVIDER_MODE,
        "external_reference": result.external_reference,
        "masked_identifier": mask_aadhaar(aadhaar_number),
        "status": VerificationStatus.identity_pending,
        "consent_given_at": _utc_now().isoformat(),
        "metadata": {"aadhaar_last4": aadhaar_number[-4:], **result.metadata},
    }).execute()
    audit(sb, user_id, "AADHAAR_OTP_REQUESTED", "OTP_SENT", {"aadhaar_last4": aadhaar_number[-4:], "demo_mode": is_demo_mode()})
    return _table_data(verification)[0]


async def verify_aadhaar_otp(sb, *, user_id: str, aadhaar_number: str, otp: str) -> None:
    verify_phone_otp(sb, user_id=user_id, phone=aadhaar_number[-4:], otp=otp, purpose="AADHAAR")
    result = await get_aadhaar_provider().verify_otp(aadhaar_number=aadhaar_number, otp=otp)
    if not result.ok:
        raise HTTPException(status_code=400, detail=result.failure_reason or "Aadhaar verification failed")
    sb.table("user_profiles").update({
        "aadhaar_verified": True,
        "aadhaar_verified_at": _utc_now().isoformat(),
        "aadhaar_reference_id": result.external_reference,
        "aadhaar_last4": aadhaar_number[-4:],
        "verification_provider": get_settings().IDENTITY_PROVIDER_MODE,
    }).eq("auth_user_id", user_id).execute()
    sb.table("identity_verifications").update({
        "status": VerificationStatus.identity_verified,
        "verified_at": _utc_now().isoformat(),
        "external_reference": result.external_reference,
    }).eq("user_id", user_id).eq("verification_type", VerificationType.aadhaar).execute()
    audit(sb, user_id, "AADHAAR_VERIFIED", "VERIFIED", {"aadhaar_last4": aadhaar_number[-4:], "demo_mode": is_demo_mode()})


def get_status(sb, *, user_id: str) -> dict:
    profile = get_profile_for_auth_user(sb, user_id)
    verifications = sb.table("identity_verifications").select("*").eq("user_id", user_id).order("requested_at", desc=True).execute()
    farmer = sb.table("farmer_profiles").select("*").eq("user_id", user_id).limit(1).execute()
    vendor = sb.table("vendor_profiles").select("*").eq("user_id", user_id).limit(1).execute()
    status = profile.get("verification_status") if profile else VerificationStatus.unverified
    role = profile.get("role") if profile else None
    return {
        "user_id": user_id,
        "role": role,
        "verification_status": status,
        "badge": verification_badge(role, status),
        "phone_verified": status in {VerificationStatus.phone_verified, VerificationStatus.identity_pending, VerificationStatus.identity_verified},
        "farmer_id_verified": bool(_table_data(farmer) and _table_data(farmer)[0].get("farmer_id_verified")),
        "vendor_verified": bool(_table_data(vendor) and _table_data(vendor)[0].get("vendor_verified")),
        "aadhaar_verified": bool(profile and profile.get("aadhaar_verified")),
        "demo_mode": is_demo_mode(),
        "verifications": _table_data(verifications),
    }


def require_verified_role(sb, *, user_id: str, role: UserRole) -> None:
    profile = get_profile_for_auth_user(sb, user_id)
    if not profile or profile.get("role") != role or profile.get("verification_status") != VerificationStatus.identity_verified:
        badge = "VERIFIED_FARMER" if role == UserRole.farmer else "VERIFIED_VENDOR"
        raise HTTPException(status_code=403, detail=f"{badge} status is required for this action")
