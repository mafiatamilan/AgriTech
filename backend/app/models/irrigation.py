from pydantic import BaseModel
from datetime import datetime


class IrrigationEvent(BaseModel):
    id: str
    farm_id: str
    scheduled_time: datetime
    started_at: datetime | None = None
    stopped_at: datetime | None = None
    status: str = "pending"
    moisture_reading: float | None = None
    created_at: datetime | None = None


class IrrigationCreate(BaseModel):
    scheduled_time: datetime


class IrrigationStatus(BaseModel):
    last_watered: datetime | None = None
    next_watering: datetime | None = None
    moisture_readings: list[dict] = []
    current_status: str | None = None
