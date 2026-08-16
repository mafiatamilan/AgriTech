from pydantic import BaseModel
from datetime import datetime


class Farm(BaseModel):
    id: str
    farmer_id: str
    name: str
    location: dict | None = None
    created_at: datetime | None = None


class FarmCreate(BaseModel):
    name: str
    latitude: float | None = None
    longitude: float | None = None


class FarmUpdate(BaseModel):
    name: str | None = None
    latitude: float | None = None
    longitude: float | None = None


class FieldArea(BaseModel):
    id: str
    farm_id: str
    area_size: float | None = None
    crop_type: str | None = None
    planted_date: str | None = None


class FieldAreaCreate(BaseModel):
    area_size: float | None = None
    crop_type: str | None = None
    planted_date: str | None = None
