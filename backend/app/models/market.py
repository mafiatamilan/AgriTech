from pydantic import BaseModel
from datetime import datetime


class DemandRequest(BaseModel):
    id: str
    farmer_id: str
    crop_name: str
    shelf_life_days: int | None = None
    harvested_date: str
    expected_price: float | None = None
    status: str = "open"
    shelf_life_expiry: datetime | None = None
    created_at: datetime | None = None


class DemandRequestCreate(BaseModel):
    crop_name: str
    shelf_life_days: int | None = None
    harvested_date: str
    expected_price: float | None = None


class RescueMatch(BaseModel):
    id: str
    demand_request_id: str
    matched_buyer_info: dict = {}
    matched_at: datetime | None = None
    status: str = "proposed"


class CropMatchRequest(BaseModel):
    crop_name: str
    shelf_life_days: int | None = None
    harvested_date: str
    expected_price: float | None = None


class CropMatchResponse(BaseModel):
    demand_request_id: str
    matches: list[dict] = []
    status: str
