"""API tests for field irrigation configuration endpoints."""
import os
import sys
from unittest.mock import patch

import pytest
from pydantic import ValidationError

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
        self._data = [{"id": "field-1", **row}]
        return self

    def update(self, row):
        existing = next((e for e in self._data if e.get("id") == "field-1"), {})
        existing.update(row)
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
        from unittest.mock import MagicMock

        return MagicMock()


def get_mock_supabase():
    return MockClient()


def test_field_area_create_rejects_non_positive_area():
    from app.models.farm import FieldAreaCreate

    with pytest.raises(ValidationError):
        FieldAreaCreate(area_size=0, crop_type="tomato", pump_flow_lpm=12)
    with pytest.raises(ValidationError):
        FieldAreaCreate(area_size=-5, crop_type="tomato", pump_flow_lpm=12)


def test_field_area_create_rejects_non_positive_pump():
    from app.models.farm import FieldAreaCreate

    with pytest.raises(ValidationError):
        FieldAreaCreate(area_size=500, pump_flow_lpm=0)
    with pytest.raises(ValidationError):
        FieldAreaCreate(area_size=500, pump_flow_lpm=-3)


@pytest.mark.asyncio
async def test_field_config_can_be_created_retrieved_updated_and_persisted():
    from app.models.farm import FieldAreaCreate, FieldAreaUpdate
    from app.routers.farms import create_field, list_fields, update_field

    mock_sb = get_mock_supabase()
    mock_sb._tables["farms"] = MockTable([{"id": "farm-1", "farmer_id": "farmer-1"}])
    mock_sb._tables["field_area"] = MockTable([])

    def _get_sb():
        return mock_sb

    with patch("app.routers.farms.get_supabase", _get_sb):
        created = await create_field(
            "farm-1",
            FieldAreaCreate(
                area_size=500,
                crop_type="tomato",
                planted_date="2026-08-10",
                soil_type="loamy",
                pump_flow_lpm=12,
            ),
            {"id": "farmer-1"},
        )
        assert created["area_size"] == 500
        assert created["pump_flow_lpm"] == 12
        assert created["soil_type"] == "loamy"

        # persisted: list returns the same row
        fields = await list_fields("farm-1", {"id": "farmer-1"})
        assert len(fields) == 1
        assert fields[0]["crop_type"] == "tomato"

        updated = await update_field(
            "farm-1",
            "field-1",
            FieldAreaUpdate(area_size=750, pump_flow_lpm=24),
            {"id": "farmer-1"},
        )
        assert updated["area_size"] == 750
        assert updated["pump_flow_lpm"] == 24
        assert updated["crop_type"] == "tomato"  # untouched value preserved

        fields = await list_fields("farm-1", {"id": "farmer-1"})
        assert fields[0]["area_size"] == 750


@pytest.mark.asyncio
async def test_field_endpoints_enforce_farm_ownership():
    from fastapi import HTTPException

    from app.models.farm import FieldAreaCreate
    from app.routers.farms import create_field, list_fields

    mock_sb = get_mock_supabase()
    mock_sb._tables["farms"] = MockTable([])  # no farm owned by this farmer
    mock_sb._tables["field_area"] = MockTable([])

    with patch("app.routers.farms.get_supabase", lambda: mock_sb):
        with pytest.raises(HTTPException) as exc:
            await create_field(
                "farm-1",
                FieldAreaCreate(area_size=500, pump_flow_lpm=12),
                {"id": "farmer-1"},
            )
        assert exc.value.status_code == 404

        with pytest.raises(HTTPException):
            await list_fields("farm-1", {"id": "farmer-1"})