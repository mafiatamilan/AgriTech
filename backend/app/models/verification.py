from enum import StrEnum
from pydantic import BaseModel, Field


class UserRole(StrEnum):
    farmer = "FARMER"
    vendor = "VENDOR"
    admin = "ADMIN"


class VerificationStatus(StrEnum):
    unverified = "UNVERIFIED"
    phone_verified = "PHONE_VERIFIED"
    identity_pending = "IDENTITY_PENDING"
    identity_verified = "IDENTITY_VERIFIED"
    identity_failed = "IDENTITY_FAILED"
    manual_review = "MANUAL_REVIEW"
    suspended = "SUSPENDED"


class VerificationType(StrEnum):
    farmer_registry = "FARMER_REGISTRY"
    enam_trader = "ENAM_TRADER"
    apmc_license = "APMC_LICENSE"
    fpo_fpc = "FPO_FPC"
    gstin = "GSTIN"
    other_agri_trader = "OTHER_AGRI_TRADER"
    aadhaar = "AADHAAR"
    phone = "PHONE"


class SignupStartRequest(BaseModel):
    email: str
    password: str
    role: UserRole
    full_name: str | None = None
    phone: str
    state: str
    district: str
    consent: bool


class SignupStartResponse(BaseModel):
    access_token: str
    refresh_token: str
    user_id: str
    role: UserRole
    verification_status: VerificationStatus
    demo_mode: bool = False


class PhoneOtpRequest(BaseModel):
    phone: str


class PhoneOtpVerifyRequest(BaseModel):
    phone: str
    otp: str = Field(min_length=4, max_length=12)


class FarmerVerificationStartRequest(BaseModel):
    full_name: str
    mobile_number: str
    state: str
    district: str
    farmer_id: str
    consent: bool


class FarmerVerificationOtpRequest(BaseModel):
    farmer_id: str
    mobile_number: str


class FarmerVerificationVerifyRequest(BaseModel):
    farmer_id: str
    mobile_number: str
    otp: str = Field(min_length=4, max_length=12)


class VendorVerificationStartRequest(BaseModel):
    business_name: str
    contact_person: str
    mobile_number: str
    state: str
    district: str
    verification_type: VerificationType
    registration_number: str
    gstin: str | None = None
    consent: bool


class VendorVerificationOtpRequest(BaseModel):
    verification_type: VerificationType
    registration_number: str
    mobile_number: str


class VendorVerificationVerifyRequest(BaseModel):
    verification_type: VerificationType
    registration_number: str
    mobile_number: str
    otp: str = Field(min_length=4, max_length=12)


class AadhaarOtpRequest(BaseModel):
    aadhaar_number: str = Field(min_length=12, max_length=12)
    consent: bool


class AadhaarOtpVerifyRequest(BaseModel):
    aadhaar_number: str = Field(min_length=12, max_length=12)
    otp: str = Field(min_length=4, max_length=12)


class VerificationActionResponse(BaseModel):
    status: VerificationStatus | str
    message: str
    verification_id: str | None = None
    masked_identifier: str | None = None
    demo_mode: bool = False
    badge: str | None = None


class VerificationStatusResponse(BaseModel):
    user_id: str
    role: UserRole | None = None
    verification_status: VerificationStatus
    badge: str | None = None
    phone_verified: bool = False
    farmer_id_verified: bool = False
    vendor_verified: bool = False
    aadhaar_verified: bool = False
    demo_mode: bool = False
    verifications: list[dict] = Field(default_factory=list)
