"""
Yield Prediction Agent — heuristic-based estimator for Indian crops.

Uses the ViT disease model to identify crop + health status, then applies
crop-specific base yields (India) adjusted by disease and weather conditions.
"""

from __future__ import annotations

import logging

logger = logging.getLogger("agritech.yield_prediction")

# Base yield ranges (kg per hectare) for major Indian crops —
# typical ranges under good conditions (source: Govt of India / ICAR).
CROP_YIELD_KG_PER_HA: dict[str, dict[str, float]] = {
    "rice": {"min": 1500, "optimal": 3000, "max": 5000},
    "wheat": {"min": 1200, "optimal": 3000, "max": 4500},
    "corn": {"min": 1500, "optimal": 3500, "max": 6000},
    "maize": {"min": 1500, "optimal": 3500, "max": 6000},
    "cotton": {"min": 300, "optimal": 500, "max": 900},
    "sugarcane": {"min": 30000, "optimal": 70000, "max": 100000},
    "soybean": {"min": 600, "optimal": 1200, "max": 2000},
    "groundnut": {"min": 800, "optimal": 1500, "max": 2500},
    "chickpea": {"min": 600, "optimal": 1200, "max": 1800},
    "pigeon pea": {"min": 500, "optimal": 1000, "max": 1500},
    "mustard": {"min": 400, "optimal": 800, "max": 1200},
    "potato": {"min": 8000, "optimal": 20000, "max": 35000},
    "tomato": {"min": 8000, "optimal": 20000, "max": 40000},
    "onion": {"min": 5000, "optimal": 12000, "max": 20000},
    "banana": {"min": 10000, "optimal": 25000, "max": 40000},
    "mango": {"min": 3000, "optimal": 8000, "max": 15000},
    "tea": {"min": 800, "optimal": 2000, "max": 3500},
}

# Default for unknown crops
DEFAULT_YIELD = {"min": 500, "optimal": 1500, "max": 3000}


def _crop_key(crop: str) -> str:
    """Normalize crop name to match our yield table."""
    c = crop.strip().lower()
    aliases = {
        "maize": "corn",
        "paddy": "rice",
        "arhar": "pigeon pea",
        "tur": "pigeon pea",
        "gram": "chickpea",
        "bengal gram": "chickpea",
        "ground nut": "groundnut",
        "jowar": "sorghum",
        "bajra": "millet",
        "ragi": "finger millet",
    }
    return aliases.get(c, c)


def _health_adjustment(disease: str, is_healthy: bool) -> tuple[float, str | None]:
    """Return a multiplier and optional risk factor based on disease status."""
    if is_healthy or disease in ("healthy", "unknown", ""):
        return 1.0, None

    adjustments = {
        "early blight": (0.75, "Early blight reduces yield by ~25%"),
        "late blight": (0.50, "Late blight can destroy 50%+ of crop if untreated"),
        "gray leaf spot": (0.70, "Gray leaf spot reduces photosynthesis and yield"),
        "common rust": (0.80, "Common rust moderately reduces yield"),
        "leaf blight": (0.70, "Leaf blight reduces effective leaf area"),
        "brown spot": (0.75, "Brown spot indicates nutrient stress + yield loss"),
        "leaf blast": (0.55, "Leaf blast is devastating — can lose 50%+ yield"),
        "yellow rust": (0.75, "Yellow rust reduces grain filling"),
        "brown rust": (0.80, "Brown rust reduces yield if widespread"),
    }

    for key, (adj, risk) in adjustments.items():
        if key in disease.lower():
            return adj, risk

    return 0.80, f"Unknown disease '{disease}' may reduce yield"


def _weather_adjustment(weather: dict | None) -> tuple[float, list[str]]:
    """Analyze weather data for conditions affecting yield."""
    if not weather:
        return 1.0, []

    risks = []
    adj = 1.0

    # Temperature
    avg_temp = weather.get("avg_temp_c") or weather.get("temp")
    max_temp = weather.get("max_temp_c")
    if avg_temp is not None:
        if avg_temp < 10:
            adj *= 0.75
            risks.append(f"Cold stress ({avg_temp:.0f}°C) — slows growth")
        elif avg_temp > 40:
            adj *= 0.70
            risks.append(f"Extreme heat ({avg_temp:.0f}°C) — causes flower/fruit drop")
        elif avg_temp > 35:
            adj *= 0.85
            risks.append(f"High temperature ({avg_temp:.0f}°C) — may stress crop")

    # Rainfall
    rainfall = weather.get("rainfall_mm_today", 0) or 0
    rainfall_forecast = weather.get("rainfall_forecast_mm_24h", 0) or 0
    total_rain = rainfall + rainfall_forecast
    if total_rain == 0:
        adj *= 0.85
        risks.append("No rainfall — irrigation needed")
    elif total_rain > 50:
        adj *= 0.80
        risks.append(f"Excessive rainfall ({total_rain:.0f}mm) — waterlogging risk")
    elif total_rain > 25:
        adj *= 0.90
        risks.append(f"Heavy rain ({total_rain:.0f}mm) — watch for drainage")

    # Humidity
    humidity = weather.get("humidity_pct", 60)
    if humidity > 85:
        adj *= 0.90
        risks.append(f"High humidity ({humidity:.0f}%) — fungal disease risk")
    elif humidity < 30:
        adj *= 0.90
        risks.append(f"Low humidity ({humidity:.0f}%) — moisture stress")

    # Condition
    condition = (weather.get("condition") or "").lower()
    if "storm" in condition or "thunder" in condition:
        adj *= 0.80
        risks.append("Storm conditions — physical damage risk")
    elif "haze" in condition or "smog" in condition:
        adj *= 0.95
        risks.append("Haze/smog — reduced sunlight for photosynthesis")

    return adj, risks


def _confidence_level(has_image: bool, has_weather: bool, disease_known: bool) -> str:
    """Estimate confidence based on available data."""
    score = 0
    if has_image:
        score += 2
    if has_weather:
        score += 1
    if disease_known:
        score += 1

    if score >= 3:
        return "high"
    if score >= 2:
        return "medium"
    return "low"


async def run_yield_prediction(
    image_url: str,
    crop_hint: str | None = None,
    disease_info: dict | None = None,
    weather_data: dict | None = None,
) -> dict:
    """Predict yield based on crop type, health, and weather conditions.

    Args:
        image_url: Path or URL to crop image.
        crop_hint: Optional crop type override.
        disease_info: Optional disease diagnosis dict from DiseasePredictionAgent.
        weather_data: Weather snapshot from weather service.

    Returns:
        {crop_type, expected_yield_kg, confidence_level, risk_factors}
    """
    # Determine crop type
    crop = (crop_hint or "unknown").strip().lower()
    if disease_info and disease_info.get("crop") and disease_info["crop"] != "unknown":
        crop = disease_info["crop"]

    crop_key = _crop_key(crop)
    base = CROP_YIELD_KG_PER_HA.get(crop_key, DEFAULT_YIELD)

    # Start with optimal yield
    yield_kg = base["optimal"]
    risks: list[str] = []

    # Adjust for disease
    is_healthy = True
    disease_name = ""
    if disease_info:
        is_healthy = disease_info.get("is_healthy", True)
        disease_name = disease_info.get("disease", "")
        if disease_name in ("uncertain", "unknown", ""):
            disease_name = ""

    health_adj, health_risk = _health_adjustment(disease_name, is_healthy)
    yield_kg *= health_adj
    if health_risk:
        risks.append(health_risk)

    # Adjust for weather conditions
    weather_adj, weather_risks = _weather_adjustment(weather_data)
    yield_kg *= weather_adj
    risks.extend(weather_risks)

    # Clamp to crop range
    yield_kg = max(base["min"], min(base["max"], yield_kg))

    # Round to reasonable precision
    yield_kg = round(yield_kg, 1)

    confidence = _confidence_level(
        has_image=bool(image_url),
        has_weather=bool(weather_data),
        disease_known=bool(disease_name),
    )

    if not risks:
        risks.append("No risk factors detected — conditions appear favorable")

    logger.debug(
        "Yield prediction: crop=%s base=%s adj=%.2f result=%.1f kg",
        crop_key, base["optimal"], health_adj * weather_adj, yield_kg,
    )

    return {
        "crop_type": crop,
        "expected_yield_kg": yield_kg,
        "confidence_level": confidence,
        "risk_factors": risks,
    }
