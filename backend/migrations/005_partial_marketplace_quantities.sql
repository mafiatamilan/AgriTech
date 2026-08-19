-- AgriTech migration 005: support partial vendor purchases.
-- Run after 001_initial_schema.sql, 002_updated.sql, 003_updated.sql,
-- and 004_ai_agent_run_impact.sql.

ALTER TABLE demand_requests
    ADD COLUMN IF NOT EXISTS quantity_kg NUMERIC,
    ADD COLUMN IF NOT EXISTS remaining_quantity_kg NUMERIC,
    ADD COLUMN IF NOT EXISTS sold_quantity_kg NUMERIC NOT NULL DEFAULT 0;

ALTER TABLE rescue_matches
    ADD COLUMN IF NOT EXISTS quantity_kg NUMERIC NOT NULL DEFAULT 0;

-- Backfill older listings from the farmer's latest matching inventory batch
-- where possible. Listings without inventory remain legacy/unquantified.
UPDATE demand_requests dr
SET quantity_kg = inv.quantity,
    remaining_quantity_kg = inv.quantity
FROM LATERAL (
    SELECT i.quantity
    FROM inventory i
    WHERE i.farm_id IN (SELECT id FROM farms WHERE farmer_id = dr.farmer_id)
      AND lower(i.crop_name) = lower(dr.crop_name)
    ORDER BY i.updated_at DESC NULLS LAST, i.id DESC
    LIMIT 1
) inv
WHERE dr.quantity_kg IS NULL;

UPDATE demand_requests
SET remaining_quantity_kg = quantity_kg
WHERE remaining_quantity_kg IS NULL
  AND quantity_kg IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_demand_requests_remaining_quantity
    ON demand_requests(remaining_quantity_kg);

-- Atomically reserve a vendor's requested quantity and create the proposed
-- match. This prevents two vendors from buying the same remaining stock.
CREATE OR REPLACE FUNCTION reserve_marketplace_quantity(
    p_demand_request_id UUID,
    p_vendor_id UUID,
    p_quantity_kg NUMERIC,
    p_buyer_info JSONB,
    p_vendor_request_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    listing demand_requests%ROWTYPE;
    match_id UUID;
    next_remaining NUMERIC;
BEGIN
    IF p_quantity_kg IS NULL OR p_quantity_kg <= 0 THEN
        RAISE EXCEPTION 'quantity_kg must be greater than zero';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM vendors WHERE id = p_vendor_id) THEN
        RAISE EXCEPTION 'vendor profile not found';
    END IF;

    SELECT * INTO listing
    FROM demand_requests
    WHERE id = p_demand_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'listing not found';
    END IF;

    IF listing.status <> 'open' THEN
        RAISE EXCEPTION 'listing is not open';
    END IF;

    IF listing.remaining_quantity_kg IS NULL THEN
        RAISE EXCEPTION 'listing quantity is not configured';
    END IF;

    IF p_quantity_kg > listing.remaining_quantity_kg THEN
        RAISE EXCEPTION 'requested quantity exceeds remaining quantity';
    END IF;

    next_remaining := listing.remaining_quantity_kg - p_quantity_kg;

    INSERT INTO rescue_matches (
        demand_request_id,
        vendor_request_id,
        matched_buyer_info,
        quantity_kg,
        status
    ) VALUES (
        p_demand_request_id,
        p_vendor_request_id,
        COALESCE(p_buyer_info, '{}'::jsonb),
        p_quantity_kg,
        'proposed'
    ) RETURNING id INTO match_id;

    UPDATE demand_requests
    SET remaining_quantity_kg = next_remaining,
        sold_quantity_kg = COALESCE(sold_quantity_kg, 0) + p_quantity_kg,
        status = CASE WHEN next_remaining <= 0 THEN 'matched' ELSE 'open' END
    WHERE id = p_demand_request_id;

    RETURN jsonb_build_object(
        'match_id', match_id,
        'remaining_quantity_kg', next_remaining
    );
END;
$$;

REVOKE ALL ON FUNCTION reserve_marketplace_quantity(UUID, UUID, NUMERIC, JSONB, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION reserve_marketplace_quantity(UUID, UUID, NUMERIC, JSONB, UUID) TO service_role;
