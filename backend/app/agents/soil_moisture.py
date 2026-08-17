"""
Soil Moisture Agent — stub implementation.

Input:  list of sensor readings (moisture_pct, recorded_at)
Output: current moisture %, estimated hours-to-next-water

TODO: Replace with real ML model (e.g. time-series forecasting)
"""

from datetime import datetime


async def analyze_moisture(readings: list[dict]) -> dict:
    if not readings:
        return {"moisture_pct": 0.0, "hours_to_next_water": 0.0, "status": "no_data"}

    latest = readings[0]
    moisture = latest.get("moisture_pct", 0.0)

    if moisture < 20:
        hours = 0.5
        status = "critical"
    elif moisture < 40:
        hours = 4.0
        status = "low"
    elif moisture < 60:
        hours = 12.0
        status = "adequate"
    else:
        hours = 24.0
        status = "optimal"

    return {
        "moisture_pct": moisture,
        "hours_to_next_water": hours,
        "status": status,
        "analyzed_at": datetime.utcnow().isoformat(),
    }
