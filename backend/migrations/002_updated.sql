-- ============================================================
-- AgriTech — Migration 002: Feature Gap Closure
-- Run AFTER migrations/001_initial_schema.sql
-- ============================================================

-- Adds:
--   - OAuth + profile fields on farmers
--   - Soil type / locality settings
--   - Hardware pairing (ESP32/LoRa)
--   - Signal strength + status feedback
--   - Vendor-side marketplace
--   - Sale confirmation on rescue_matches
--   - Chat-based upload agent
--   - Expanded notification types
--   - Water-saved convenience view

-- ============================================================
-- 1. FARMERS: OAuth + settings fields
-- ============================================================

ALTER TABLE farmers
    ADD COLUMN IF NOT EXISTS oauth_provider TEXT,
    ADD COLUMN IF NOT EXISTS avatar_url TEXT,
    ADD COLUMN IF NOT EXISTS soil_type TEXT,
    ADD COLUMN IF NOT EXISTS area_locality TEXT;


-- ============================================================
-- 2. NOTIFICATIONS: expand notification types
-- ============================================================

ALTER TABLE notifications
    DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE notifications
    ADD CONSTRAINT notifications_type_check
    CHECK (
        type IN (
            'watering',
            'match',
            'system',
            'agent_result',
            'shelf_life_expiring',
            'sale_confirmed',
            'device_status',
            'vendor_match'
        )
    );


-- ============================================================
-- 3. HARDWARE PAIRING
-- ============================================================

CREATE TABLE IF NOT EXISTS farm_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL
        REFERENCES farms(id) ON DELETE CASCADE,

    device_type TEXT NOT NULL DEFAULT 'esp32'
        CHECK (device_type IN ('esp32', 'sim_module')),

    device_uid TEXT NOT NULL UNIQUE,

    device_secret_hash TEXT NOT NULL,

    last_signal_strength INTEGER,

    last_seen_at TIMESTAMPTZ,

    motor_relay_state TEXT DEFAULT 'off'
        CHECK (
            motor_relay_state IN ('on', 'off', 'unknown')
        ),

    firmware_version TEXT,

    paired_at TIMESTAMPTZ DEFAULT now()
);


CREATE TABLE IF NOT EXISTS hardware_status_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    farm_device_id UUID NOT NULL
        REFERENCES farm_devices(id) ON DELETE CASCADE,

    event_type TEXT NOT NULL
        CHECK (
            event_type IN (
                'heartbeat',
                'motor_on',
                'motor_off',
                'error'
            )
        ),

    signal_strength INTEGER,

    payload JSONB NOT NULL DEFAULT '{}',

    received_at TIMESTAMPTZ DEFAULT now()
);


-- Add signal strength to existing sensor readings
ALTER TABLE sensor_readings
    ADD COLUMN IF NOT EXISTS signal_strength INTEGER;


-- ============================================================
-- 4. VENDOR-SIDE MARKETPLACE
-- ============================================================

CREATE TABLE IF NOT EXISTS vendors (
    id UUID PRIMARY KEY
        REFERENCES auth.users(id) ON DELETE CASCADE,

    business_name TEXT NOT NULL,

    contact_phone TEXT,

    contact_email TEXT,

    address TEXT,

    location GEOGRAPHY(POINT, 4326),

    created_at TIMESTAMPTZ DEFAULT now()
);


CREATE TABLE IF NOT EXISTS vendor_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    vendor_id UUID NOT NULL
        REFERENCES vendors(id) ON DELETE CASCADE,

    crop_name TEXT NOT NULL,

    quantity_needed NUMERIC,

    expected_price NUMERIC,

    status TEXT DEFAULT 'open'
        CHECK (
            status IN (
                'open',
                'matched',
                'expired',
                'cancelled'
            )
        ),

    created_at TIMESTAMPTZ DEFAULT now()
);


-- ============================================================
-- 5. RESCUE MATCHES
-- ============================================================

ALTER TABLE rescue_matches
    ADD COLUMN IF NOT EXISTS vendor_request_id UUID
        REFERENCES vendor_requests(id) ON DELETE CASCADE,

    ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMPTZ;


-- demand_request_id was NOT NULL in migration 001.
-- A rescue match can now originate from either:
--   1. demand_requests
--   2. vendor_requests

ALTER TABLE rescue_matches
    ALTER COLUMN demand_request_id DROP NOT NULL;


-- Only add the constraint if it doesn't already exist.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'rescue_matches_one_origin_chk'
          AND conrelid = 'rescue_matches'::regclass
    ) THEN
        ALTER TABLE rescue_matches
            ADD CONSTRAINT rescue_matches_one_origin_chk
            CHECK (
                (
                    demand_request_id IS NOT NULL
                    AND vendor_request_id IS NULL
                )
                OR
                (
                    demand_request_id IS NULL
                    AND vendor_request_id IS NOT NULL
                )
            );
    END IF;
END
$$;


-- ============================================================
-- 7. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_farm_devices_farm_id
    ON farm_devices(farm_id);

CREATE INDEX IF NOT EXISTS idx_farm_devices_device_uid
    ON farm_devices(device_uid);

CREATE INDEX IF NOT EXISTS idx_hardware_status_events_device_id
    ON hardware_status_events(farm_device_id);

CREATE INDEX IF NOT EXISTS idx_hardware_status_events_received_at
    ON hardware_status_events(received_at);

CREATE INDEX IF NOT EXISTS idx_vendor_requests_vendor_id
    ON vendor_requests(vendor_id);

CREATE INDEX IF NOT EXISTS idx_vendor_requests_status
    ON vendor_requests(status);

CREATE INDEX IF NOT EXISTS idx_rescue_matches_vendor_request_id
    ON rescue_matches(vendor_request_id);

-- ============================================================
-- 8. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE farm_devices ENABLE ROW LEVEL SECURITY;

ALTER TABLE hardware_status_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE vendors ENABLE ROW LEVEL SECURITY;

ALTER TABLE vendor_requests ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 8A. FARM DEVICES
-- ============================================================

DROP POLICY IF EXISTS farm_devices_select
ON farm_devices;

CREATE POLICY farm_devices_select
ON farm_devices
FOR SELECT
USING (
    farm_id IN (
        SELECT id
        FROM farms
        WHERE farmer_id = public.farmer_id()
    )
);


DROP POLICY IF EXISTS farm_devices_insert
ON farm_devices;

CREATE POLICY farm_devices_insert
ON farm_devices
FOR INSERT
WITH CHECK (
    farm_id IN (
        SELECT id
        FROM farms
        WHERE farmer_id = public.farmer_id()
    )
);


DROP POLICY IF EXISTS farm_devices_update
ON farm_devices;

CREATE POLICY farm_devices_update
ON farm_devices
FOR UPDATE
USING (
    farm_id IN (
        SELECT id
        FROM farms
        WHERE farmer_id = public.farmer_id()
    )
);


-- ============================================================
-- 8B. HARDWARE STATUS EVENTS
-- ============================================================

DROP POLICY IF EXISTS hardware_status_events_select
ON hardware_status_events;

CREATE POLICY hardware_status_events_select
ON hardware_status_events
FOR SELECT
USING (
    farm_device_id IN (
        SELECT fd.id
        FROM farm_devices fd
        JOIN farms f
            ON f.id = fd.farm_id
        WHERE f.farmer_id = public.farmer_id()
    )
);


-- ============================================================
-- 8C. VENDORS
-- ============================================================

DROP POLICY IF EXISTS vendors_select
ON vendors;

CREATE POLICY vendors_select
ON vendors
FOR SELECT
USING (
    id = auth.uid()
);


DROP POLICY IF EXISTS vendors_insert
ON vendors;

CREATE POLICY vendors_insert
ON vendors
FOR INSERT
WITH CHECK (
    id = auth.uid()
);


DROP POLICY IF EXISTS vendors_update
ON vendors;

CREATE POLICY vendors_update
ON vendors
FOR UPDATE
USING (
    id = auth.uid()
);


-- ============================================================
-- 8D. VENDOR REQUESTS
-- ============================================================

DROP POLICY IF EXISTS vendor_requests_select_own
ON vendor_requests;

CREATE POLICY vendor_requests_select_own
ON vendor_requests
FOR SELECT
USING (
    vendor_id = auth.uid()
);


DROP POLICY IF EXISTS vendor_requests_select_open
ON vendor_requests;

CREATE POLICY vendor_requests_select_open
ON vendor_requests
FOR SELECT
USING (
    status = 'open'
);


DROP POLICY IF EXISTS vendor_requests_insert
ON vendor_requests;

CREATE POLICY vendor_requests_insert
ON vendor_requests
FOR INSERT
WITH CHECK (
    vendor_id = auth.uid()
);


DROP POLICY IF EXISTS vendor_requests_update
ON vendor_requests;

CREATE POLICY vendor_requests_update
ON vendor_requests
FOR UPDATE
USING (
    vendor_id = auth.uid()
);


-- ============================================================
-- 9. CONVENIENCE VIEW
-- ============================================================

CREATE OR REPLACE VIEW farmer_water_saved_totals AS
SELECT
    farmer_id,
    COALESCE(SUM(value), 0) AS total_water_saved_liters
FROM impact_metrics
WHERE metric_type = 'water_saved_liters'
GROUP BY farmer_id;
