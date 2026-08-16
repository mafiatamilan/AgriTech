from pydantic import BaseModel
from datetime import datetime


class Notification(BaseModel):
    id: str
    farmer_id: str
    type: str
    title: str
    body: str
    related_id: str | None = None
    read_at: datetime | None = None
    created_at: datetime | None = None


class NotificationCreate(BaseModel):
    farmer_id: str
    type: str
    title: str
    body: str
    related_id: str | None = None
