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


async def run_demand_matching(demand_request: dict, sb=None, agent_run_id: str | None = None) -> list[dict]:
    crop = (demand_request.get("crop_name") or "").strip()
    if not crop or sb is None:
        return []

    vr = sb.table("vendor_requests") \
        .select("*, vendors(business_name, reliability_score, contact_phone, contact_email, address)") \
        .eq("crop_name", crop) \
        .eq("status", "open") \
        .execute()
    rows = vr.data or []
    if not rows:
        return []
    vendor_ids = [row.get("vendor_id") for row in rows if row.get("vendor_id")]
    verified_vendor_ids: set[str] = set()
    if vendor_ids:
        profiles = sb.table("user_profiles").select("auth_user_id, verification_status, role") \
            .in_("auth_user_id", vendor_ids) \
            .eq("role", "VENDOR") \
            .eq("verification_status", "IDENTITY_VERIFIED") \
            .execute()
        verified_vendor_ids = {row["auth_user_id"] for row in profiles.data or []}

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
        quantity_kg=float(demand_request.get("remaining_quantity_kg") or demand_request.get("quantity_kg") or 1.0),
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
    vendors_by_id = {}
    for row in rows:
        vendor = row.get("vendors") or {}
        if not isinstance(vendor, dict):
            vendor = {}
        vendors_by_id[row.get("vendor_id", "")] = vendor
        buyer_demands.append(
            BuyerDemand(
                buyer_id=row.get("vendor_id", ""),
                buyer_name=vendor.get("business_name") or "Vendor",
                crop=crop,
                quantity_requested_kg=float(row.get("quantity_needed") or 0.0),
                offered_price_per_kg=float(row.get("expected_price") or 0.0),
                distance_km=0.0,  # no geo distance computed yet
                pickup_in_hours=24.0,
                buyer_reliability=min(
                    1.0,
                    float(vendor.get("reliability_score") or 0.8)
                    + (0.15 if row.get("vendor_id") in verified_vendor_ids else 0.0),
                ),
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
            "buyer_farmer_id": m.buyer_id,
            "buyer_phone": vendors_by_id.get(m.buyer_id, {}).get("contact_phone"),
            "buyer_email": vendors_by_id.get(m.buyer_id, {}).get("contact_email"),
            "buyer_address": vendors_by_id.get(m.buyer_id, {}).get("address"),
            "buyer_location": "Nearby",
            "offered_price": m.offered_price_per_kg,
            "distance_km": m.distance_km,
            "shelf_life_compatible": True,
            "vendor_verified": m.buyer_id in verified_vendor_ids,
            "reason": m.recommendation,
            "reason_labels": list(m.reason_labels),
            "quantity_to_sell_kg": min(
                float(demand_request.get("remaining_quantity_kg") or demand_request.get("quantity_kg") or 0.0),
                float(next((r.get("quantity_needed") or 0.0 for r in rows if r.get("vendor_id") == m.buyer_id), 0.0)),
            ),
            "matched_at": datetime.utcnow().isoformat(),
        }
        for m in result.top_matches
    ]
