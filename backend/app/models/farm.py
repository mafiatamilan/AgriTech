from pydantic import BaseModel, Field
from datetime import datetime


class Farm(BaseModel):
    id: str
    farmer_id: str
    name: str
    location: dict | None = None
    latitude: float | None = None
    longitude: float | None = None
    soil_type: str | None = None
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
    field_name: str | None = None
    area_size: float | None = None
    crop_type: str | None = None
    planted_date: str | None = None
    soil_type: str | None = None
    pump_flow_lpm: float | None = None


class FieldAreaCreate(BaseModel):
    field_name: str | None = None
    area_size: float | None = Field(default=None, gt=0)
    crop_type: str | None = None
    planted_date: str | None = None
    soil_type: str | None = None
    pump_flow_lpm: float | None = Field(default=None, gt=0)


class FieldAreaUpdate(BaseModel):
    field_name: str | None = None
    area_size: float | None = Field(default=None, gt=0)
    crop_type: str | None = None
    planted_date: str | None = None
    soil_type: str | None = None
    pump_flow_lpm: float | None = Field(default=None, gt=0)
