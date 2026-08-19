"""Weather snapshot service.

Uses Open-Meteo (free, no API key) as primary provider, falls back to
OpenWeatherMap if configured, and finally to defaults. Never blocks app
flows on a weather outage.
"""

import httpx
from datetime import datetime

from app.core.config import get_settings
from app.core.logging_config import get_logger

settings = get_settings()
logger = get_logger("app.services.weather")

DEFAULT_WEATHER = {
    "avg_temp_c": 24.0,
    "max_temp_c": 28.0,
    "humidity_pct": 65.0,
    "rainfall_mm_today": 0.0,
    "rainfall_forecast_mm_24h": 0.0,
    "sunlight_hours": 7.0,
    "wind_speed_kmph": 8.0,
    "condition": "clear",
}

# WMO weather codes -> simple condition labels
WMO_CODES = {
    0: "clear", 1: "clear", 2: "clouds", 3: "clouds",
    45: "fog", 48: "fog",
    51: "drizzle", 53: "drizzle", 55: "drizzle",
    56: "drizzle", 57: "drizzle",
    61: "rain", 63: "rain", 65: "rain",
    66: "rain", 67: "rain",
    71: "snow", 73: "snow", 75: "snow", 77: "snow",
    80: "rain", 81: "rain", 82: "rain",
    85: "snow", 86: "snow",
    95: "storm", 96: "storm", 99: "storm",
}


async def get_weather_snapshot(
    sb,
    farm_id: str,
    field_id: str | None = None,
    crop: str | None = None,
    farm_lat: float | None = None,
    farm_lon: float | None = None,
) -> dict:
    data = dict(DEFAULT_WEATHER)
    source = "backend_default"
    logger.debug("weather snapshot requested farm=%s", farm_id)
    try:
        data = await _fetch_open_meteo(farm_lat, farm_lon)
        source = "open_meteo"
    except Exception as exc:
        logger.debug("Open-Meteo failed (%s), trying OpenWeatherMap", exc)
        try:
            data = await _fetch_openweathermap(farm_lat, farm_lon)
            source = "openweathermap"
        except Exception as exc2:
            logger.warning("All weather providers failed (%s) - using defaults", exc2)

    row = {
        "farm_id": farm_id,
        "field_id": field_id,
        "crop": crop,
        **data,
        "source": source,
        "recorded_at": datetime.utcnow().isoformat(),
    }
    resp = sb.table("weather_snapshots").insert(row).execute()
    if resp.data:
        row["id"] = resp.data[0]["id"]
    return row


async def _fetch_open_meteo(farm_lat: float | None, farm_lon: float | None) -> dict:
    if farm_lat is None or farm_lon is None:
        raise RuntimeError("farm coordinates unavailable")

    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": farm_lat,
                "longitude": farm_lon,
                "current": "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m",
                "daily": "temperature_2m_max,temperature_2m_min,precipitation_sum,sunshine_duration",
                "timezone": "auto",
                "forecast_days": 2,
            },
        )
        resp.raise_for_status()
        d = resp.json()

    current = d.get("current", {})
    daily = d.get("daily", {})

    temp = current.get("temperature_2m")
    humidity = current.get("relative_humidity_2m")
    wind_kph = current.get("wind_speed_10m")
    wmo = current.get("weather_code", 0)

    max_temps = daily.get("temperature_2m_max", [])
    min_temps = daily.get("temperature_2m_min", [])
    precip = daily.get("precipitation_sum", [])
    sunshine_hrs = daily.get("sunshine_duration", [])

    max_temp = max_temps[0] if max_temps else (temp + 4 if temp else None)
    rainfall_today = precip[0] if precip else 0.0
    rainfall_tomorrow = precip[1] if len(precip) > 1 else 0.0
    sunlight = (sunshine_hrs[0] / 3600) if sunshine_hrs and sunshine_hrs[0] else 7.0

    return {
        "avg_temp_c": temp,
        "max_temp_c": max_temp,
        "humidity_pct": humidity,
        "rainfall_mm_today": rainfall_today,
        "rainfall_forecast_mm_24h": rainfall_tomorrow,
        "sunlight_hours": round(sunlight, 1),
        "wind_speed_kmph": round(wind_kph or 0.0, 1),
        "condition": WMO_CODES.get(wmo, "clear"),
    }


async def _fetch_openweathermap(farm_lat: float | None, farm_lon: float | None) -> dict:
    if not settings.WEATHER_API_KEY or not settings.WEATHER_API_BASE_URL:
        raise RuntimeError("OpenWeatherMap not configured")
    if farm_lat is None or farm_lon is None:
        raise RuntimeError("farm coordinates unavailable")

    async with httpx.AsyncClient(timeout=8.0) as client:
        resp = await client.get(
            f"{settings.WEATHER_API_BASE_URL}/weather",
            params={"lat": farm_lat, "lon": farm_lon, "appid": settings.WEATHER_API_KEY, "units": "metric"},
        )
        resp.raise_for_status()
        d = resp.json()

    main = d.get("main", {})
    weather = (d.get("weather") or [{}])[0]
    wind = d.get("wind", {})
    rain = d.get("rain", {})
    return {
        "avg_temp_c": main.get("temp"),
        "max_temp_c": main.get("temp_max"),
        "humidity_pct": main.get("humidity"),
        "rainfall_mm_today": rain.get("1h", rain.get("3h", 0.0)),
        "rainfall_forecast_mm_24h": 0.0,
        "sunlight_hours": DEFAULT_WEATHER["sunlight_hours"],
        "wind_speed_kmph": round((wind.get("speed") or 0.0) * 3.6, 1),
        "condition": (weather.get("main") or "clear").lower(),
    }
