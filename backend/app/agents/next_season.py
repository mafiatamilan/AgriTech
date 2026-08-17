"""
Next Season Recommendation Agent — stub implementation.

Input:  historical yield + soil data
Output: crop/planting recommendations for next season

TODO: Plug in real agronomic recommendation model
"""

from datetime import datetime


async def recommend_next_season(farm_id: str, historical_data: dict) -> dict:
    return {
        "recommended_crops": [
            {"crop": "Maize", "confidence": 0.91, "reason": "High yield history, favorable soil"},
            {"crop": "Beans", "confidence": 0.85, "reason": "Good rotation crop, nitrogen fixing"},
            {"crop": "Sweet Potato", "confidence": 0.78, "reason": "Drought tolerant, market demand"},
        ],
        "planting_window": "2026-03-01 to 2026-04-15",
        "soil_preparation": "Apply compost 2 weeks before planting",
        "note": "stub — replace with real agronomic model",
        "generated_at": datetime.utcnow().isoformat(),
    }
