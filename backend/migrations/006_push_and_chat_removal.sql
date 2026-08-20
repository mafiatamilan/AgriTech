-- AgriTech migration 006: push notification tokens.
-- Run after 001-005.

CREATE TABLE IF NOT EXISTS device_push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id UUID NOT NULL REFERENCES farmers(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    platform TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_device_push_tokens_farmer_id
    ON device_push_tokens(farmer_id);

-- Partial marketplace reservations need both the farmer listing
-- (`demand_request_id`) and the vendor intent (`vendor_request_id`) on the
-- same match row, so remove the older either/or constraint.
ALTER TABLE rescue_matches
    DROP CONSTRAINT IF EXISTS rescue_matches_one_origin_chk;

ALTER TABLE device_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS device_push_tokens_select_own ON device_push_tokens;
CREATE POLICY device_push_tokens_select_own
ON device_push_tokens
FOR SELECT
USING (farmer_id = auth.uid());

DROP POLICY IF EXISTS device_push_tokens_insert_own ON device_push_tokens;
CREATE POLICY device_push_tokens_insert_own
ON device_push_tokens
FOR INSERT
WITH CHECK (farmer_id = auth.uid());

DROP POLICY IF EXISTS device_push_tokens_update_own ON device_push_tokens;
CREATE POLICY device_push_tokens_update_own
ON device_push_tokens
FOR UPDATE
USING (farmer_id = auth.uid())
WITH CHECK (farmer_id = auth.uid());
