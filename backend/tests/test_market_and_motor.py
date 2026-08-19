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

    def in_(self, col, vals):
        return self

    def filter(self, col, op, val):
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

    def table(self, name):
        if name not in self._tables:
            self._tables[name] = MockTable()
        return self._tables[name]

    @property
    def auth(self):
        return MagicMock()


def get_mock_supabase():
    return MockClient()


def get_mock_supabase_admin():
    return MockClient()


@pytest.mark.asyncio
async def test_crop_match_returns_response():
    mock_sb = get_mock_supabase()
    mock_sb._tables["vendor_requests"] = MockTable([])
    mock_sb._tables["rescue_matches"] = MockTable([{
        "id": "match-1",
        "demand_request_id": "req-1",
        "matched_buyer_info": {"buyer_name": "Vendor A", "offered_price": 10.0},
    }])

    def _get_sb():
        return mock_sb

    with patch("app.routers.market.get_supabase", _get_sb):
        from app.routers.market import crop_match
        from app.models.market import DemandRequestCreate

        req = DemandRequestCreate(
            crop_name="Maize",
            shelf_life_days=7,
            harvested_date="2026-08-10",
            expected_price=15.0,
        )
        result = await crop_match(req, {"id": "test-farmer-id"})
        assert result.status in ("open", "matched")
        assert result.demand_request_id is not None


@pytest.mark.asyncio
async def test_stop_current_with_no_running():
    with patch("app.routers.motor.get_supabase", get_mock_supabase):
        from app.services.irrigation_service import IrrigationService
        sb = get_mock_supabase()
        svc = IrrigationService(sb)
        result = await svc.stop_current("farm-123")
        assert result["status"] == "no_running_event"


@pytest.mark.asyncio
async def test_cancel_next_with_no_pending():
    with patch("app.routers.motor.get_supabase", get_mock_supabase):
        from app.services.irrigation_service import IrrigationService
        sb = get_mock_supabase()
        svc = IrrigationService(sb)
        result = await svc.cancel_next("farm-123")
        assert result["status"] == "no_pending_event"
