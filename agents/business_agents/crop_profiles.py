from __future__ import annotations

from .models import CropProfile


DEFAULT_CROP_PROFILES: dict[str, CropProfile] = {
    "tomato": CropProfile(
        crop="tomato",
        plant_type="fruiting",
        base_shelf_life_days=7,
        ideal_temp_min_c=12,
        ideal_temp_max_c=18,
        ideal_humidity_min_pct=85,
        ideal_humidity_max_pct=95,
        temp_sensitivity=0.85,
        humidity_sensitivity=0.6,
        rain_sensitivity=0.45,
    ),
    "spinach": CropProfile(
        crop="spinach",
        plant_type="leafy",
        base_shelf_life_days=3,
        ideal_temp_min_c=0,
        ideal_temp_max_c=5,
        ideal_humidity_min_pct=90,
        ideal_humidity_max_pct=98,
        temp_sensitivity=1.25,
        humidity_sensitivity=1.05,
        rain_sensitivity=0.8,
        damage_sensitivity=1.2,
    ),
    "okra": CropProfile(
        crop="okra",
        plant_type="fruiting",
        base_shelf_life_days=5,
        ideal_temp_min_c=7,
        ideal_temp_max_c=10,
        ideal_humidity_min_pct=90,
        ideal_humidity_max_pct=95,
        temp_sensitivity=0.9,
        humidity_sensitivity=0.7,
        rain_sensitivity=0.45,
    ),
    "onion": CropProfile(
        crop="onion",
        plant_type="bulb",
        base_shelf_life_days=45,
        ideal_temp_min_c=0,
        ideal_temp_max_c=20,
        ideal_humidity_min_pct=55,
        ideal_humidity_max_pct=70,
        temp_sensitivity=0.35,
        humidity_sensitivity=0.65,
        rain_sensitivity=0.55,
    ),
    "potato": CropProfile(
        crop="potato",
        plant_type="tuber",
        base_shelf_life_days=30,
        ideal_temp_min_c=7,
        ideal_temp_max_c=12,
        ideal_humidity_min_pct=85,
        ideal_humidity_max_pct=95,
        temp_sensitivity=0.45,
        humidity_sensitivity=0.45,
        rain_sensitivity=0.3,
    ),
    "mango": CropProfile(
        crop="mango",
        plant_type="fruit",
        base_shelf_life_days=8,
        ideal_temp_min_c=10,
        ideal_temp_max_c=13,
        ideal_humidity_min_pct=85,
        ideal_humidity_max_pct=90,
        temp_sensitivity=0.8,
        humidity_sensitivity=0.55,
        rain_sensitivity=0.35,
    ),
}


def normalize_crop_name(crop: str) -> str:
    return crop.strip().lower().replace("_", " ")


def get_crop_profile(crop: str, profiles: dict[str, CropProfile] | None = None) -> CropProfile:
    profile_map = profiles or DEFAULT_CROP_PROFILES
    key = normalize_crop_name(crop)
    if key not in profile_map:
        raise KeyError(f"No crop profile found for '{crop}'. Add one before running shelf-life logic.")
    return profile_map[key]
