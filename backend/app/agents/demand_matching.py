"""
Demand Matching Agent — stub implementation.

Input:  demand_requests row
Output: list of matching buyers/inventory

TODO: Replace with real matching algorithm (proximity + price + shelf life)
"""

from datetime import datetime


async def run_demand_matching(demand_request: dict) -> list[dict]:
    crop = demand_request.get("crop_name", "")
    price = demand_request.get("expected_price", 0)

    # Stub: return mock matches
    return [
        {
            "buyer_name": f"Market Hub - {crop.title()}",
            "buyer_location": "Nearby",
            "offered_price": price * 0.95 if price else 10.0,
            "distance_km": 5.2,
            "shelf_life_compatible": True,
            "match_score": 0.87,
            "matched_at": datetime.utcnow().isoformat(),
        },
    ]
