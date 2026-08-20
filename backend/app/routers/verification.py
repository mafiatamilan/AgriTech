from fastapi import APIRouter, Depends, HTTPException
from app.core.deps import get_current_farmer
from app.db.supabase_client import get_supabase
from app.models.verification import (
    AadhaarOtpRequest,
    AadhaarOtpVerifyRequest,
    FarmerVerificationOtpRequest,
    FarmerVerificationStartRequest,
    FarmerVerificationVerifyRequest,
    PhoneOtpRequest,
    PhoneOtpVerifyRequest,
    VerificationActionResponse,
    VerificationStatusResponse,
    VendorVerificationOtpRequest,
    VendorVerificationStartRequest,
    VendorVerificationVerifyRequest,
)
from app.services.identity_verification_service import (
    get_status,
    is_demo_mode,
    mask_aadhaar,
    mask_identifier,
    request_aadhaar_otp,
    send_farmer_otp,
    send_phone_otp,
    send_vendor_otp,
    start_farmer_verification,
    start_vendor_verification,
    verification_badge,
    verify_aadhaar_otp,
    verify_farmer,
    verify_phone_otp,
    verify_vendor,
)

router = APIRouter(tags=["verification"])


@router.post("/auth/phone/send-otp", response_model=VerificationActionResponse)
async def phone_send_otp(
    req: PhoneOtpRequest,
    current_user: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    send_phone_otp(sb, user_id=current_user["id"], phone=req.phone)
    return VerificationActionResponse(
        status="OTP_SENT",
        message="OTP sent to mobile number" + (" (DEMO OTP: 123456)" if is_demo_mode() else ""),
        masked_identifier=mask_identifier(req.phone),
        demo_mode=is_demo_mode(),
    )


@router.post("/auth/phone/verify-otp", response_model=VerificationActionResponse)
async def phone_verify_otp(
    req: PhoneOtpVerifyRequest,
    current_user: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    verify_phone_otp(sb, user_id=current_user["id"], phone=req.phone, otp=req.otp)
    return VerificationActionResponse(
        status="PHONE_VERIFIED",
        message="Phone number verified",
        masked_identifier=mask_identifier(req.phone),
        demo_mode=is_demo_mode(),
    )


@router.post("/verification/farmer/start", response_model=VerificationActionResponse)
async def farmer_start(
    req: FarmerVerificationStartRequest,
    current_user: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    row = await start_farmer_verification(sb, user_id=current_user["id"], req=req)
    return VerificationActionResponse(
        status=row.get("status", "IDENTITY_PENDING"),
        message="Farmer identity check started" if row.get("status") != "IDENTITY_FAILED" else row.get("failure_reason", "Farmer identity check failed"),
        verification_id=row.get("id"),
        masked_identifier=mask_identifier(req.farmer_id),
        demo_mode=is_demo_mode(),
    )


@router.post("/verification/farmer/send-otp", response_model=VerificationActionResponse)
async def farmer_send_otp(
    req: FarmerVerificationOtpRequest,
    current_user: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    await send_farmer_otp(
        sb,
        user_id=current_user["id"],
        farmer_id=req.farmer_id,
        mobile_number=req.mobile_number,
    )
    return VerificationActionResponse(
        status="OTP_SENT",
        message="Farmer registry OTP sent" + (" (DEMO OTP: 123456)" if is_demo_mode() else ""),
        masked_identifier=mask_identifier(req.farmer_id),
        demo_mode=is_demo_mode(),
    )


@router.post("/verification/farmer/verify", response_model=VerificationActionResponse)
async def farmer_verify(
    req: FarmerVerificationVerifyRequest,
    current_user: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    await verify_farmer(sb, user_id=current_user["id"], req=req)
    return VerificationActionResponse(
        status="IDENTITY_VERIFIED",
        message="Farmer ID and mobile ownership verified",
        masked_identifier=mask_identifier(req.farmer_id),
        demo_mode=is_demo_mode(),
        badge="VERIFIED_FARMER",
    )


@router.post("/verification/vendor/start", response_model=VerificationActionResponse)
async def vendor_start(
    req: VendorVerificationStartRequest,
    current_user: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    row = await start_vendor_verification(sb, user_id=current_user["id"], req=req)
    return VerificationActionResponse(
        status=row.get("status", "IDENTITY_PENDING"),
        message="Vendor credential check started" if row.get("status") != "IDENTITY_FAILED" else row.get("failure_reason", "Vendor credential check failed"),
        verification_id=row.get("id"),
        masked_identifier=mask_identifier(req.registration_number),
        demo_mode=is_demo_mode(),
    )


@router.post("/verification/vendor/send-otp", response_model=VerificationActionResponse)
async def vendor_send_otp(
    req: VendorVerificationOtpRequest,
    current_user: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    await send_vendor_otp(sb, user_id=current_user["id"], req=req)
    return VerificationActionResponse(
        status="OTP_SENT",
        message="Vendor credential OTP sent" + (" (DEMO OTP: 123456)" if is_demo_mode() else ""),
        masked_identifier=mask_identifier(req.registration_number),
        demo_mode=is_demo_mode(),
    )


@router.post("/verification/vendor/verify", response_model=VerificationActionResponse)
async def vendor_verify(
    req: VendorVerificationVerifyRequest,
    current_user: dict = Depends(get_current_farmer),
):
    sb = get_supabase()
    await verify_vendor(sb, user_id=current_user["id"], req=req)
    return VerificationActionResponse(
        status="IDENTITY_VERIFIED",
        message="Vendor credential and mobile ownership verified",
        masked_identifier=mask_identifier(req.registration_number),
        demo_mode=is_demo_mode(),
        badge="VERIFIED_VENDOR",
    )


@router.post("/verification/aadhaar/request-otp", response_model=VerificationActionResponse)
async def aadhaar_request_otp_route(
    req: AadhaarOtpRequest,
    current_user: dict = Depends(get_current_farmer),
):
    if not req.aadhaar_number.isdigit():
        raise HTTPException(status_code=422, detail="Aadhaar number must contain 12 digits")
    sb = get_supabase()
    row = await request_aadhaar_otp(
        sb,
        user_id=current_user["id"],
        aadhaar_number=req.aadhaar_number,
        consent=req.consent,
    )
    return VerificationActionResponse(
        status="OTP_SENT",
        message="Aadhaar OTP requested through configured provider" + (" (DEMO OTP: 123456)" if is_demo_mode() else ""),
        verification_id=row.get("id"),
        masked_identifier=mask_aadhaar(req.aadhaar_number),
        demo_mode=is_demo_mode(),
    )


@router.post("/verification/aadhaar/verify-otp", response_model=VerificationActionResponse)
async def aadhaar_verify_otp_route(
    req: AadhaarOtpVerifyRequest,
    current_user: dict = Depends(get_current_farmer),
):
    if not req.aadhaar_number.isdigit():
        raise HTTPException(status_code=422, detail="Aadhaar number must contain 12 digits")
    sb = get_supabase()
    await verify_aadhaar_otp(
        sb,
        user_id=current_user["id"],
        aadhaar_number=req.aadhaar_number,
        otp=req.otp,
    )
    return VerificationActionResponse(
        status="IDENTITY_VERIFIED",
        message="Optional Aadhaar KYC verified",
        masked_identifier=mask_aadhaar(req.aadhaar_number),
        demo_mode=is_demo_mode(),
    )


@router.get("/verification/status", response_model=VerificationStatusResponse)
async def verification_status(current_user: dict = Depends(get_current_farmer)):
    sb = get_supabase()
    status = get_status(sb, user_id=current_user["id"])
    status["badge"] = verification_badge(status.get("role"), status.get("verification_status"))
    return status
