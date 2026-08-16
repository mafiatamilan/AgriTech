from pydantic import BaseModel
from datetime import datetime


class CropImage(BaseModel):
    id: str
    farm_id: str
    image_url: str
    uploaded_at: datetime | None = None
    analysis_status: str = "pending"


class CropImageStatus(BaseModel):
    id: str
    analysis_status: str
    health_result: dict | None = None
    yield_result: dict | None = None
