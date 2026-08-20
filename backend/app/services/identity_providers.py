from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime, UTC
from app.core.config import get_settings


@dataclass
class ProviderResult:
    ok: bool
    status: str
    external_reference: str | None = None
    registered_mobile: str | None = None
    failure_reason: str | None = None
    metadata: dict = field(default_factory=dict)


class FarmerIdentityProvider(ABC):
    @abstractmethod
    async def verify_farmer_id(
        self,
        *,
        farmer_id: str,
        mobile_number: str,
        state: str,
        district: str,
        full_name: str,
    ) -> ProviderResult:
        raise NotImplementedError

    @abstractmethod
    async def send_otp(self, *, farmer_id: str, mobile_number: str) -> ProviderResult:
        raise NotImplementedError

    @abstractmethod
    async def verify_otp(self, *, farmer_id: str, mobile_number: str, otp: str) -> ProviderResult:
        raise NotImplementedError

    @abstractmethod
    async def get_verification_status(self, *, external_reference: str) -> ProviderResult:
        raise NotImplementedError


class VendorIdentityProvider(ABC):
    @abstractmethod
    async def verify_registration(
        self,
        *,
        verification_type: str,
        registration_number: str,
        mobile_number: str,
        state: str,
        district: str,
        business_name: str,
    ) -> ProviderResult:
        raise NotImplementedError

    @abstractmethod
    async def send_otp(
        self,
        *,
        verification_type: str,
        registration_number: str,
        mobile_number: str,
    ) -> ProviderResult:
        raise NotImplementedError

    @abstractmethod
    async def verify_otp(
        self,
        *,
        verification_type: str,
        registration_number: str,
        mobile_number: str,
        otp: str,
    ) -> ProviderResult:
        raise NotImplementedError

    @abstractmethod
    async def get_verification_status(self, *, external_reference: str) -> ProviderResult:
        raise NotImplementedError


class AadhaarVerificationProvider(ABC):
    @abstractmethod
    async def request_otp(self, *, aadhaar_number: str) -> ProviderResult:
        raise NotImplementedError

    @abstractmethod
    async def verify_otp(self, *, aadhaar_number: str, otp: str) -> ProviderResult:
        raise NotImplementedError


class MockFarmerIdentityProvider(FarmerIdentityProvider):
    demo_farmer_id = "FARMER-DEMO-001"
    demo_mobile = "9999999999"
    demo_otp = "123456"

    async def verify_farmer_id(self, **kwargs) -> ProviderResult:
        farmer_id = kwargs["farmer_id"].strip().upper()
        mobile = kwargs["mobile_number"].strip()
        ok = farmer_id == self.demo_farmer_id and mobile == self.demo_mobile
        return ProviderResult(
            ok=ok,
            status="MATCHED" if ok else "NOT_MATCHED",
            external_reference=f"mock-farmer-{farmer_id}",
            registered_mobile=self.demo_mobile if ok else None,
            failure_reason=None if ok else "Mock mode accepts FARMER-DEMO-001 with 9999999999 only",
            metadata={"provider_mode": "mock", "verified_at": datetime.now(UTC).isoformat()} if ok else {"provider_mode": "mock"},
        )

    async def send_otp(self, *, farmer_id: str, mobile_number: str) -> ProviderResult:
        return ProviderResult(
            ok=True,
            status="OTP_SENT",
            external_reference=f"mock-farmer-otp-{farmer_id.strip().upper()}",
            registered_mobile=mobile_number,
            metadata={"provider_mode": "mock", "demo_otp": self.demo_otp},
        )

    async def verify_otp(self, *, farmer_id: str, mobile_number: str, otp: str) -> ProviderResult:
        ok = (
            farmer_id.strip().upper() == self.demo_farmer_id
            and mobile_number.strip() == self.demo_mobile
            and otp == self.demo_otp
        )
        return ProviderResult(
            ok=ok,
            status="VERIFIED" if ok else "FAILED",
            external_reference=f"mock-farmer-verified-{farmer_id.strip().upper()}",
            registered_mobile=mobile_number if ok else None,
            failure_reason=None if ok else "Invalid mock farmer OTP or identity",
            metadata={"provider_mode": "mock"},
        )

    async def get_verification_status(self, *, external_reference: str) -> ProviderResult:
        return ProviderResult(ok=True, status="MOCK_STATUS", external_reference=external_reference, metadata={"provider_mode": "mock"})


class MockVendorIdentityProvider(VendorIdentityProvider):
    demo_registration = "VENDOR-DEMO-001"
    demo_mobile = "8888888888"
    demo_otp = "123456"

    async def verify_registration(self, **kwargs) -> ProviderResult:
        registration = kwargs["registration_number"].strip().upper()
        mobile = kwargs["mobile_number"].strip()
        ok = registration == self.demo_registration and mobile == self.demo_mobile
        return ProviderResult(
            ok=ok,
            status="MATCHED" if ok else "NOT_MATCHED",
            external_reference=f"mock-vendor-{registration}",
            registered_mobile=self.demo_mobile if ok else None,
            failure_reason=None if ok else "Mock mode accepts VENDOR-DEMO-001 with 8888888888 only",
            metadata={"provider_mode": "mock"},
        )

    async def send_otp(self, *, verification_type: str, registration_number: str, mobile_number: str) -> ProviderResult:
        return ProviderResult(
            ok=True,
            status="OTP_SENT",
            external_reference=f"mock-vendor-otp-{registration_number.strip().upper()}",
            registered_mobile=mobile_number,
            metadata={"provider_mode": "mock", "demo_otp": self.demo_otp},
        )

    async def verify_otp(self, *, verification_type: str, registration_number: str, mobile_number: str, otp: str) -> ProviderResult:
        ok = (
            registration_number.strip().upper() == self.demo_registration
            and mobile_number.strip() == self.demo_mobile
            and otp == self.demo_otp
        )
        return ProviderResult(
            ok=ok,
            status="VERIFIED" if ok else "FAILED",
            external_reference=f"mock-vendor-verified-{registration_number.strip().upper()}",
            registered_mobile=mobile_number if ok else None,
            failure_reason=None if ok else "Invalid mock vendor OTP or credential",
            metadata={"provider_mode": "mock"},
        )

    async def get_verification_status(self, *, external_reference: str) -> ProviderResult:
        return ProviderResult(ok=True, status="MOCK_STATUS", external_reference=external_reference, metadata={"provider_mode": "mock"})


class MockAadhaarVerificationProvider(AadhaarVerificationProvider):
    demo_otp = "123456"

    async def request_otp(self, *, aadhaar_number: str) -> ProviderResult:
        return ProviderResult(
            ok=True,
            status="OTP_SENT",
            external_reference=f"mock-aadhaar-{aadhaar_number[-4:]}",
            metadata={"provider_mode": "mock", "demo_otp": self.demo_otp},
        )

    async def verify_otp(self, *, aadhaar_number: str, otp: str) -> ProviderResult:
        ok = otp == self.demo_otp
        return ProviderResult(
            ok=ok,
            status="VERIFIED" if ok else "FAILED",
            external_reference=f"mock-aadhaar-verified-{aadhaar_number[-4:]}",
            failure_reason=None if ok else "Invalid mock Aadhaar OTP",
            metadata={"provider_mode": "mock"},
        )


class FutureFarmerRegistryProvider(FarmerIdentityProvider):
    async def verify_farmer_id(self, **kwargs) -> ProviderResult:
        return ProviderResult(ok=False, status="NOT_CONFIGURED", failure_reason="Authorized Farmer Registry integration is not configured")

    async def send_otp(self, **kwargs) -> ProviderResult:
        return ProviderResult(ok=False, status="NOT_CONFIGURED", failure_reason="Authorized Farmer Registry OTP integration is not configured")

    async def verify_otp(self, **kwargs) -> ProviderResult:
        return ProviderResult(ok=False, status="NOT_CONFIGURED", failure_reason="Authorized Farmer Registry OTP verification is not configured")

    async def get_verification_status(self, *, external_reference: str) -> ProviderResult:
        return ProviderResult(ok=False, status="NOT_CONFIGURED", external_reference=external_reference)


class FutureVendorRegistryProvider(VendorIdentityProvider):
    async def verify_registration(self, **kwargs) -> ProviderResult:
        return ProviderResult(ok=False, status="NOT_CONFIGURED", failure_reason="Authorized vendor credential provider is not configured")

    async def send_otp(self, **kwargs) -> ProviderResult:
        return ProviderResult(ok=False, status="NOT_CONFIGURED", failure_reason="Authorized vendor OTP provider is not configured")

    async def verify_otp(self, **kwargs) -> ProviderResult:
        return ProviderResult(ok=False, status="NOT_CONFIGURED", failure_reason="Authorized vendor OTP verification is not configured")

    async def get_verification_status(self, *, external_reference: str) -> ProviderResult:
        return ProviderResult(ok=False, status="NOT_CONFIGURED", external_reference=external_reference)


class AuthorizedAadhaarVerificationProvider(AadhaarVerificationProvider):
    async def request_otp(self, *, aadhaar_number: str) -> ProviderResult:
        return ProviderResult(ok=False, status="NOT_CONFIGURED", failure_reason="Authorized UIDAI AUA/KUA/ASA integration is not configured")

    async def verify_otp(self, *, aadhaar_number: str, otp: str) -> ProviderResult:
        return ProviderResult(ok=False, status="NOT_CONFIGURED", failure_reason="Authorized UIDAI AUA/KUA/ASA integration is not configured")


def get_farmer_identity_provider() -> FarmerIdentityProvider:
    return MockFarmerIdentityProvider() if get_settings().IDENTITY_PROVIDER_MODE == "mock" else FutureFarmerRegistryProvider()


def get_vendor_identity_provider() -> VendorIdentityProvider:
    return MockVendorIdentityProvider() if get_settings().IDENTITY_PROVIDER_MODE == "mock" else FutureVendorRegistryProvider()


def get_aadhaar_provider() -> AadhaarVerificationProvider:
    return MockAadhaarVerificationProvider() if get_settings().IDENTITY_PROVIDER_MODE == "mock" else AuthorizedAadhaarVerificationProvider()
