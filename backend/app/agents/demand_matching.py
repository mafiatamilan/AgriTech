"""
Demand Matching Agent — wired to the real `business_agents.DemandMatchingAgent`.

Input:  demand_requests row
Output: list of matching buyers/vendors ranked by the agent (max 3),
        without the internal match_score.

Buyer demand comes from open `vendor_requests` rows. The farmer's available
batch is built from the demand request itself (quantity is not tracked on
`demand_requests`, so scoring degrades gracefully to price/reliability).
"""

from datetime import date, datetime, timedelta

from app.agents.runtime import agents


async def run_demand_matching(demand_request: dict, sb=None) -> list[dict]:
    crop = (demand_request.get("crop_name") or "").strip()
    if not crop or sb is None:
        return []

    vr = sb.table("vendor_requests") \
        .select("*, vendors(business_name, reliability_score)") \
        .eq("crop_name", crop) \
        .eq("status", "open") \
        .execute()
    rows = vr.data or []
    if not rows:
        return []

    biz = agents()["business"]
    from business_agents.models import (
        BuyerDemand,
        InventoryStatus,
        ShelfLifeEstimate,
        StorageType,
        Urgency,
    )

    harvested = date.fromisoformat(str(demand_request.get("harvested_date"))[:10])
    shelf_days = float(demand_request.get("shelf_life_days") or 7)
    expiry = demand_request.get("shelf_life_expiry")
    sell_by = (
        date.fromisoformat(str(expiry)[:10])
        if expiry
        else harvested + timedelta(days=int(shelf_days))
    )
    remaining = (sell_by - date.today()).days
    if remaining <= 0:
        urgency = Urgency.EXPIRED_RISK
    elif remaining <= 1:
        urgency = Urgency.URGENT
    elif remaining <= 2:
        urgency = Urgency.HIGH
    elif remaining <= 5:
        urgency = Urgency.MEDIUM
    else:
        urgency = Urgency.LOW

    inventory = InventoryStatus(
        batch_id=demand_request.get("id", ""),
        crop=crop,
        # ponytail: demand_requests has no quantity column; score is still
        # driven by price/reliability/distance. Add quantity if the flow grows it.
        quantity_kg=1.0,
        quality_grade="A",
        harvest_date=harvested,
        storage_type=StorageType.AMBIENT,
        shelf_life=ShelfLifeEstimate(
            crop=crop,
            plant_type="",
            estimated_shelf_life_days=shelf_days,
            remaining_shelf_life_days=max(0.0, float(remaining)),
            sell_by_date=sell_by,
            urgency=urgency,
            spoilage_risk="high" if urgency in (Urgency.URGENT, Urgency.EXPIRED_RISK) else "low",
            recommendation="",
            factors=(),
        ),
    )

    buyer_demands = []
    for row in rows:
        vendor = row.get("vendors") or {}
        if not isinstance(vendor, dict):
            vendor = {}
        buyer_demands.append(
            BuyerDemand(
                buyer_id=row.get("vendor_id", ""),
                buyer_name=vendor.get("business_name") or "Vendor",
                crop=crop,
                quantity_requested_kg=float(row.get("quantity_needed") or 0.0),
                offered_price_per_kg=float(row.get("expected_price") or 0.0),
                distance_km=0.0,  # no geo distance computed yet
                pickup_in_hours=24.0,
                buyer_reliability=float(vendor.get("reliability_score") or 0.8),
                transport_available=True,
            )
        )

    result = biz.DemandMatchingAgent().recommend_top_matches(
        inventory=inventory,
        buyer_demands=buyer_demands,
        transport_weather=None,
        limit=3,
    )

    return [
        {
            "buyer_name": m.buyer_name,
            "buyer_location": "Nearby",
            "offered_price": m.offered_price_per_kg,
            "distance_km": m.distance_km,
            "shelf_life_compatible": True,
            "reason": m.recommendation,
            "reason_labels": list(m.reason_labels),
            "matched_at": datetime.utcnow().isoformat(),
        }
        for m in result.top_matches
    ]