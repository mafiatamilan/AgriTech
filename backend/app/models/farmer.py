from pydantic import BaseModel
from datetime import datetime


class Farmer(BaseModel):
    id: str
    name: str
    phone: str | None = None
    email: str | None = None
    preferred_language: str = "en"
    created_at: datetime | None = None


class FarmerCreate(BaseModel):
    name: str
    phone: str | None = None
    email: str | None = None
    preferred_language: str = "en"


class FarmerUpdate(BaseModel):
    name: str | None = None
    phone: str | None = None
    email: str | None = None
    preferred_language: str | None = None
