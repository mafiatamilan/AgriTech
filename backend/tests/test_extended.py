import pytest
import sys
import os
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


class MockTable:
    def __init__(self, data=None):
        self._data = data or []
        self._filters = {}

    def select(self, *args):
        return self

    def eq(self, col, val):
        self._filters[col] = val
        return self

    def neq(self, col, val):
        return self

    def in_(self, col, vals):
        return self

    def filter(self, col, op, val):
        return self

    def not_(self):
        return self

    def is_(self, col, val):
        return self

    def gte(self, col, val):
        return self

    def lte(self, col, val):
        return self

    def order(self, col, desc=False):
        return self

    def limit(self, n):
        return self

    def execute(self):
        return self

    def insert(self, row):
        row_with_id = {"id": "mock-id-0", **row}
        self._data = [row_with_id]
        return self

    def update(self, row):
        return self

    def delete(self):
        return self

    @property
    def data(self):
        return self._data


class MockClient:
    def __init__(self):
        self._tables = {}
        self.auth = MagicMock()

    def table(self, name):
        if name not in self._tables:
            self._tables[name] = MockTable()
        return self._tables[name]


def get_mock_supabase():
    return MockClient()


def get_mock_supabase_admin():
    return MockClient()


# ============================================================
# OAuth exchange tests
# ============================================================

@pytest.mark.asyncio
async def test_oauth_exchange_existing_user():
    mock_sb = get_mock_supabase()
    mock_sb._tables["farmers"] = MockTable([{
        "id": "user-123",
        "name": "Test Farmer",
        "email": "test@example.com",
        "preferred_language": "en",
        "soil_type": None,
        "area_locality": None,
    }])

    def _get_sb():
        return mock_sb

    with patch("app.routers.auth.get_supabase", _get_sb):
        from app.routers.auth import oauth_exchange, OAuthExchangeRequest

        with patch("app.routers.auth.decode_jwt", return_value={"sub": "user-123"}):
            result = await oauth_exchange(OAuthExchangeRequest(access_token="fake-token"))
        assert result.is_new_user is False
        assert result.profile.id == "user-123"


@pytest.mark.asyncio
async def test_oauth_exchange_new_user():
    mock_sb = get_mock_supabase()
    mock_sb._tables["farmers"] = MockTable([])  # no existing farmer

    mock_user = MagicMock()
    mock_user.user_metadata = {"full_name": "New User"}
    mock_user.email = "new@example.com"
    mock_sb.auth.get_user.return_value = MagicMock(user=mock_user)

    def _get_sb():
        return mock_sb

    with patch("app.routers.auth.get_supabase", _get_sb):
        from app.routers.auth import oauth_exchange, OAuthExchangeRequest

        with patch("app.routers.auth.decode_jwt", return_value={"sub": "new-user-456"}):
            result = await oauth_exchange(OAuthExchangeRequest(access_token="fake-token"))
        assert result.is_new_user is True
        assert result.profile.name == "New User"


# ============================================================
# Device pairing tests
# ============================================================

@pytest.mark.asyncio
async def test_pair_device():
    mock_sb = get_mock_supabase()
    mock_sb._tables["farms"] = MockTable([{"id": "farm-1"}])
    mock_sb._tables["farm_devices"] = MockTable([{
        "id": "dev-1",
        "farm_id": "farm-1",
        "device_uid": "esp32-001",
        "last_signal_strength": None,
        "motor_relay_state": "off",
        "last_seen_at": None,
    }])

    def _get_sb():
        return mock_sb

    with patch("app.routers.farms.get_supabase", _get_sb):
        from app.routers.farms import pair_device, DevicePairRequest

        result = await pair_device(
            "farm-1",
            DevicePairRequest(device_uid="esp32-001", device_secret="secret123"),
            {"id": "farmer-1"},
        )
        assert result["device_uid"] == "esp32-001"
        assert "device_secret_hash" not in result


# ============================================================
# Confirm-sale tests
# ============================================================

@pytest.mark.asyncio
async def test_confirm_match():
    mock_sb = get_mock_supabase()
    mock_sb._tables["rescue_matches"] = MockTable([{
        "id": "match-1",
        "demand_request_id": "req-1",
        "matched_buyer_info": {},
        "demand_requests": {"farmer_id": "farmer-1", "crop_name": "Maize"},
    }])
    mock_sb._tables["demand_requests"] = MockTable([{
        "id": "req-1",
        "farmer_id": "farmer-1",
    }])

    def _get_sb():
        return mock_sb

    with patch("app.routers.market.get_supabase", _get_sb):
        from app.routers.market import confirm_match

        result = await confirm_match("match-1", {"id": "farmer-1"})
        assert result["status"] == "confirmed"
        assert result["match_id"] == "match-1"


@pytest.mark.asyncio
async def test_confirm_match_wrong_farmer():
    mock_sb = get_mock_supabase()
    mock_sb._tables["rescue_matches"] = MockTable([{
        "id": "match-1",
        "demand_request_id": "req-1",
        "matched_buyer_info": {},
        "demand_requests": {"farmer_id": "farmer-1", "crop_name": "Maize"},
    }])
    mock_sb._tables["demand_requests"] = MockTable([{
        "id": "req-1",
        "farmer_id": "farmer-1",
    }])

    def _get_sb():
        return mock_sb

    with patch("app.routers.market.get_supabase", _get_sb):
        from app.routers.market import confirm_match
        from fastapi import HTTPException

        with pytest.raises(HTTPException) as exc_info:
            await confirm_match("match-1", {"id": "wrong-farmer"})
        assert exc_info.value.status_code == 403


# ============================================================
# Vendor tests
# ============================================================

@pytest.mark.asyncio
async def test_vendor_signup():
    mock_sb = get_mock_supabase()
    mock_sb._tables["vendors"] = MockTable([])  # no existing

    def _get_sb():
        return mock_sb

    with patch("app.routers.vendors.get_supabase", _get_sb):
        from app.routers.vendors import vendor_signup, VendorSignupRequest

        result = await vendor_signup(
            VendorSignupRequest(name="Test Vendor", business_name="Fresh Produce Co"),
            {"id": "user-1"},
        )
        assert result["status"] == "created"


@pytest.mark.asyncio
async def test_create_vendor_request():
    mock_sb = get_mock_supabase()
    mock_sb._tables["vendors"] = MockTable([{"id": "vendor-1"}])
    mock_sb._tables["vendor_requests"] = MockTable([{
        "id": "vr-1",
        "vendor_id": "vendor-1",
        "crop_name": "Maize",
    }])

    def _get_sb():
        return mock_sb

    with patch("app.routers.vendors.get_supabase", _get_sb):
        from app.routers.vendors import create_vendor_request, VendorRequestCreate

        result = await create_vendor_request(
            VendorRequestCreate(crop_name="Maize", quantity_needed=100),
            {"id": "vendor-1"},
        )
        assert result["crop_name"] == "Maize"


# ============================================================
# Water-saved test
# ============================================================

@pytest.mark.asyncio
async def test_water_saved_no_data():
    mock_sb = get_mock_supabase()

    def _get_sb():
        return mock_sb

    with patch("app.routers.account.get_supabase", _get_sb):
        from app.routers.account import get_water_saved

        result = await get_water_saved({"id": "farmer-1"})
        assert result["total_water_saved_liters"] == 0


# ============================================================
# Chat session test
# ============================================================

@pytest.mark.asyncio
async def test_create_chat_session():
    mock_sb = get_mock_supabase()
    mock_sb._tables["chat_sessions"] = MockTable([{
        "id": "session-1",
        "created_at": "2026-08-17T00:00:00",
    }])

    def _get_sb():
        return mock_sb

    with patch("app.routers.chat.get_supabase", _get_sb):
        from app.routers.chat import create_session, CreateSessionRequest

        result = await create_session(
            CreateSessionRequest(farm_id="farm-1"),
            {"id": "farmer-1"},
        )
        assert result["id"] is not None
