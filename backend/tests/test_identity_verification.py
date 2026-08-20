import pytest
from fastapi import HTTPException


@pytest.mark.asyncio
async def test_mock_farmer_provider_accepts_only_demo_identity():
    from app.services.identity_providers import MockFarmerIdentityProvider

    provider = MockFarmerIdentityProvider()
    ok = await provider.verify_farmer_id(
        farmer_id="FARMER-DEMO-001",
        mobile_number="9999999999",
        state="Tamil Nadu",
        district="Chennai",
        full_name="Demo Farmer",
    )
    bad = await provider.verify_farmer_id(
        farmer_id="FARMER-DEMO-002",
        mobile_number="9999999999",
        state="Tamil Nadu",
        district="Chennai",
        full_name="Demo Farmer",
    )

    assert ok.ok is True
    assert ok.metadata["provider_mode"] == "mock"
    assert bad.ok is False


@pytest.mark.asyncio
async def test_mock_vendor_provider_accepts_only_demo_identity():
    from app.services.identity_providers import MockVendorIdentityProvider

    provider = MockVendorIdentityProvider()
    ok = await provider.verify_registration(
        verification_type="ENAM_TRADER",
        registration_number="VENDOR-DEMO-001",
        mobile_number="8888888888",
        state="Tamil Nadu",
        district="Chennai",
        business_name="Demo Buyer",
    )
    bad = await provider.verify_otp(
        verification_type="ENAM_TRADER",
        registration_number="VENDOR-DEMO-001",
        mobile_number="8888888888",
        otp="000000",
    )

    assert ok.ok is True
    assert bad.ok is False


def test_aadhaar_masking_keeps_only_last_four():
    from app.services.identity_verification_service import mask_aadhaar, mask_identifier

    assert mask_aadhaar("123412341234") == "XXXX XXXX 1234"
    assert mask_identifier("FARMER-DEMO-001").endswith("O001")
    assert "FARMER-DEMO-001" not in mask_identifier("FARMER-DEMO-001")


def test_verification_contract_accepts_vendor_payload():
    from app.models.verification import VendorVerificationStartRequest

    req = VendorVerificationStartRequest.model_validate({
        "business_name": "Demo Buyer",
        "contact_person": "Buyer One",
        "mobile_number": "8888888888",
        "state": "Tamil Nadu",
        "district": "Chennai",
        "verification_type": "ENAM_TRADER",
        "registration_number": "VENDOR-DEMO-001",
        "gstin": "22AAAAA0000A1Z5",
        "consent": True,
    })

    assert req.verification_type == "ENAM_TRADER"
    assert req.consent is True


class _Resp:
    def __init__(self, data):
        self.data = data


class _Table:
    def __init__(self, data):
        self._data = data

    def select(self, *args):
        return self

    def eq(self, col, val):
        self._data = [row for row in self._data if row.get(col) == val]
        return self

    def limit(self, n):
        self._data = self._data[:n]
        return self

    def execute(self):
        return _Resp(self._data)


class _Sb:
    def __init__(self, profile):
        self.profile = profile

    def table(self, name):
        assert name == "user_profiles"
        return _Table([self.profile] if self.profile else [])


def test_marketplace_safety_requires_verified_role():
    from app.models.verification import UserRole
    from app.services.identity_verification_service import require_verified_role

    require_verified_role(
        _Sb({"auth_user_id": "u1", "role": "FARMER", "verification_status": "IDENTITY_VERIFIED"}),
        user_id="u1",
        role=UserRole.farmer,
    )

    with pytest.raises(HTTPException) as exc:
        require_verified_role(
            _Sb({"auth_user_id": "u2", "role": "VENDOR", "verification_status": "PHONE_VERIFIED"}),
            user_id="u2",
            role=UserRole.vendor,
        )
    assert exc.value.status_code == 403
