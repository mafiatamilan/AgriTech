from __future__ import annotations

from .models import CropCalendar


DEFAULT_CROP_CALENDARS: dict[str, CropCalendar] = {
    "tomato": CropCalendar("tomato", 7, 25, 45, 65, 95, 120),
    "okra": CropCalendar("okra", 6, 20, 35, 50, 75, 95),
    "spinach": CropCalendar("spinach", 5, 15, 28, 38, 45, 55),
    "onion": CropCalendar("onion", 10, 35, 70, 95, 120, 150),
    "potato": CropCalendar("potato", 12, 30, 55, 75, 95, 120),
    "maize": CropCalendar("maize", 7, 25, 50, 70, 95, 120),
}


def normalize_crop_name(crop: str) -> str:
    return crop.strip().lower().replace("_", " ")


def get_crop_calendar(crop: str, calendars: dict[str, CropCalendar] | None = None) -> CropCalendar | None:
    return (calendars or DEFAULT_CROP_CALENDARS).get(normalize_crop_name(crop))
