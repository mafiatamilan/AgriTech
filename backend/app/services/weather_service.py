"""Weather snapshot service.

Normalizes provider data into the `weather_snapshots` schema and persists it
so AI agents receive backend data instead of calling the weather provider
directly. Never blocks app flows on a weather outage — falls back to defaults.
"""

import httpx
from datetime import datetime

from app.core.config import get_settings

settings = get_settings()

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


async def get_weather_snapshot(
    sb,
    farm_id: str,
    field_id: str | None = None,
    crop: str | None = None,
    farm_lat: float | None = None,
    farm_lon: float | None = None,
) -> dict:
    """Fetch + normalize weather, persist a weather_snapshots row, return it."""
    data = dict(DEFAULT_WEATHER)
    source = "backend_default"
    try:
        data = await _fetch_from_provider(farm_lat, farm_lon)
        source = "weather_api"
    except Exception:
        pass  # ponytail: weather outage must not break irrigation/inventory flows

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


async def _fetch_from_provider(farm_lat: float | None, farm_lon: float | None) -> dict:
    if not settings.WEATHER_API_KEY or not settings.WEATHER_API_BASE_URL:
        raise RuntimeError("weather API not configured")
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