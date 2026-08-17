-- ============================================================
-- AgriTech — Migration 003: AI Agent Storage Extension
-- ============================================================
--
-- RUN AFTER:
--   001_initial_schema.sql
--   002_feature_gap_closure.sql
--
-- Purpose:
--   Extend the existing AgriTech schema to support the newer
--   AI-engineering agent storage requirements without creating
--   duplicate versions of existing tables.
--
-- ============================================================

BEGIN;


-- ============================================================
-- 1. FARM / FIELD EXTENSIONS
-- ============================================================

ALTER TABLE farms
    ADD COLUMN IF NOT EXISTS location_text TEXT,
    ADD COLUMN IF NOT EXISTS latitude NUMERIC,
    ADD COLUMN IF NOT EXISTS longitude NUMERIC,
    ADD COLUMN IF NOT EXISTS soil_type TEXT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();


ALTER TABLE field_area
    ADD COLUMN IF NOT EXISTS field_name TEXT,
    ADD COLUMN IF NOT EXISTS soil_type TEXT,
    ADD COLUMN IF NOT EXISTS growth_stage TEXT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();


-- ============================================================
-- 2. FARMER SETTINGS / NOTIFICATION PREFERENCES
-- ============================================================

ALTER TABLE farmers
    ADD COLUMN IF NOT EXISTS notification_prefs JSONB
        NOT NULL DEFAULT '{
            "watering": true,
            "match": true,
            "system": true
        }'::jsonb,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();


-- ============================================================
-- 3. WEATHER SNAPSHOTS
-- ============================================================

CREATE TABLE IF NOT EXISTS weather_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    farm_id UUID NOT NULL
        REFERENCES farms(id) ON DELETE CASCADE,

    field_id UUID
        REFERENCES field_area(id) ON DELETE SET NULL,

    crop TEXT,

    avg_temp_c NUMERIC,
    max_temp_c NUMERIC,
    humidity_pct NUMERIC,
    rainfall_mm_today NUMERIC,
    rainfall_forecast_mm_24h NUMERIC,
    sunlight_hours NUMERIC,
    wind_speed_kmph NUMERIC,

    condition TEXT,

    source TEXT NOT NULL DEFAULT 'weather_api',

    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS idx_weather_snapshots_farm
    ON weather_snapshots(farm_id);


CREATE INDEX IF NOT EXISTS idx_weather_snapshots_recorded
    ON weather_snapshots(recorded_at DESC);


-- ============================================================
-- 4. EXTEND EXISTING CROP IMAGE STORAGE
-- ============================================================

ALTER TABLE crop_images
    ADD COLUMN IF NOT EXISTS field_id UUID
        REFERENCES field_area(id) ON DELETE SET NULL,

    ADD COLUMN IF NOT EXISTS farmer_id UUID
        REFERENCES farmers(id) ON DELETE CASCADE,

    ADD COLUMN IF NOT EXISTS crop_hint TEXT,

    ADD COLUMN IF NOT EXISTS failure_reason TEXT,

    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ
        DEFAULT now();


-- Support lifecycle:
-- pending -> processing -> done / failed

ALTER TABLE crop_images
    DROP CONSTRAINT IF EXISTS crop_images_analysis_status_check;


ALTER TABLE crop_images
    ADD CONSTRAINT crop_images_analysis_status_check
    CHECK (
        analysis_status IN (
            'pending',
            'processing',
            'done',
            'failed'
        )
    );


CREATE INDEX IF NOT EXISTS idx_crop_images_farmer
    ON crop_images(farmer_id);


CREATE INDEX IF NOT EXISTS idx_crop_images_field
    ON crop_images(field_id);


-- ============================================================
-- 5. EXTEND AGENT RESULTS
-- ============================================================

ALTER TABLE agent_results
    ADD COLUMN IF NOT EXISTS field_id UUID
        REFERENCES field_area(id) ON DELETE SET NULL,

    ADD COLUMN IF NOT EXISTS image_upload_id UUID
        REFERENCES crop_images(id) ON DELETE SET NULL,

    ADD COLUMN IF NOT EXISTS model_name TEXT,

    ADD COLUMN IF NOT EXISTS model_version TEXT;


-- Existing agent_type constraint only has:
--   health, yield, next_season
--
-- Replace it with the expanded AI-agent set.

ALTER TABLE agent_results
    DROP CONSTRAINT IF EXISTS agent_results_agent_type_check;


ALTER TABLE agent_results
    ADD CONSTRAINT agent_results_agent_type_check
    CHECK (
        agent_type IN (
            'health',
            'yield',
            'next_season',
            'irrigation',
            'inventory',
            'demand_matching',
            'smart_supervisor'
        )
    );


CREATE INDEX IF NOT EXISTS idx_agent_results_agent_type
    ON agent_results(agent_type);


CREATE INDEX IF NOT EXISTS idx_agent_results_image
    ON agent_results(image_upload_id);


-- ============================================================
-- 6. DISEASE DIAGNOSES
-- ============================================================

CREATE TABLE IF NOT EXISTS disease_diagnoses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    farm_id UUID NOT NULL
        REFERENCES farms(id) ON DELETE CASCADE,

    field_id UUID
        REFERENCES field_area(id) ON DELETE SET NULL,

    image_upload_id UUID NOT NULL
        REFERENCES crop_images(id) ON DELETE CASCADE,

    predicted_crop TEXT,

    predicted_disease TEXT,

    is_healthy BOOLEAN,

    confidence_level TEXT,

    -- Internal numerical confidence.
    -- Do NOT expose this directly to farmer UI unless explicitly required.
    raw_confidence NUMERIC,

    severity TEXT,

    recommendation TEXT,

    remedies JSONB NOT NULL DEFAULT '[]'::jsonb,

    prevention JSONB NOT NULL DEFAULT '[]'::jsonb,

    retake_image BOOLEAN NOT NULL DEFAULT false,

    reason_labels JSONB NOT NULL DEFAULT '[]'::jsonb,

    model_source TEXT,

    model_name TEXT,

    model_version TEXT,

    labels_version TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS idx_disease_diagnoses_farm
    ON disease_diagnoses(farm_id);


CREATE INDEX IF NOT EXISTS idx_disease_diagnoses_image
    ON disease_diagnoses(image_upload_id);


-- ============================================================
-- 7. IRRIGATION DECISIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS irrigation_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    farm_id UUID NOT NULL
        REFERENCES farms(id) ON DELETE CASCADE,

    field_id UUID
        REFERENCES field_area(id) ON DELETE SET NULL,

    weather_snapshot_id UUID
        REFERENCES weather_snapshots(id) ON DELETE SET NULL,

    soil_type TEXT,

    crop TEXT,

    growth_stage TEXT,

    moisture_pct NUMERIC,

    rainfall_forecast_mm_24h NUMERIC,

    decision TEXT NOT NULL
        CHECK (
            decision IN (
                'water_now',
                'delay',
                'skip',
                'monitor'
            )
        ),

    recommended_duration_minutes INTEGER,

    recommended_start_at TIMESTAMPTZ,

    reasoning TEXT,

    confidence NUMERIC,

    agent_result JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS idx_irrigation_decisions_farm
    ON irrigation_decisions(farm_id);


CREATE INDEX IF NOT EXISTS idx_irrigation_decisions_created
    ON irrigation_decisions(created_at DESC);


-- ============================================================
-- 8. MQTT / HARDWARE COMMAND QUEUE
-- ============================================================
--
-- The backend can use this as the canonical command/audit table.
-- The MVP ESP32 transport remains HTTP polling because the existing
-- backend architecture explicitly uses long-polling for devices
-- behind NAT.
--

CREATE TABLE IF NOT EXISTS mqtt_commands (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    farm_id UUID NOT NULL
        REFERENCES farms(id) ON DELETE CASCADE,

    farm_device_id UUID
        REFERENCES farm_devices(id) ON DELETE CASCADE,

    irrigation_event_id UUID
        REFERENCES irrigation_events(id) ON DELETE SET NULL,

    command_type TEXT NOT NULL
        CHECK (
            command_type IN (
                'motor_on',
                'motor_off',
                'heartbeat',
                'status_request'
            )
        ),

    payload JSONB NOT NULL DEFAULT '{}'::jsonb,

    publish_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (
            publish_status IN (
                'pending',
                'sent',
                'acknowledged',
                'failed',
                'expired'
            )
        ),

    issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    sent_at TIMESTAMPTZ,

    acknowledged_at TIMESTAMPTZ,

    error_message TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS idx_mqtt_commands_device
    ON mqtt_commands(farm_device_id);


CREATE INDEX IF NOT EXISTS idx_mqtt_commands_status
    ON mqtt_commands(publish_status);


-- ============================================================
-- 9. EXTEND HARDWARE STATUS
-- ============================================================

ALTER TABLE farm_devices
    ADD COLUMN IF NOT EXISTS health_status TEXT,

    ADD COLUMN IF NOT EXISTS last_moisture_pct NUMERIC,

    ADD COLUMN IF NOT EXISTS last_temperature_c NUMERIC,

    ADD COLUMN IF NOT EXISTS last_humidity_pct NUMERIC,

    ADD COLUMN IF NOT EXISTS last_error TEXT;


ALTER TABLE hardware_status_events
    ADD COLUMN IF NOT EXISTS moisture_pct NUMERIC,

    ADD COLUMN IF NOT EXISTS temperature_c NUMERIC,

    ADD COLUMN IF NOT EXISTS humidity_pct NUMERIC,

    ADD COLUMN IF NOT EXISTS battery_voltage NUMERIC,

    ADD COLUMN IF NOT EXISTS firmware_version TEXT;


-- ============================================================
-- 10. INVENTORY BATCH EXTENSIONS
-- ============================================================
--
-- Reuse existing inventory table instead of creating a duplicate
-- inventory_batches table.
--

ALTER TABLE inventory
    ADD COLUMN IF NOT EXISTS storage_type TEXT,

    ADD COLUMN IF NOT EXISTS quality_grade TEXT,

    ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'available',

    ADD COLUMN IF NOT EXISTS field_id UUID
        REFERENCES field_area(id) ON DELETE SET NULL,

    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();


ALTER TABLE inventory
    DROP CONSTRAINT IF EXISTS inventory_status_check;


ALTER TABLE inventory
    ADD CONSTRAINT inventory_status_check
    CHECK (
        status IN (
            'available',
            'matched',
            'sold',
            'expired',
            'cancelled'
        )
    );


-- ============================================================
-- 11. INVENTORY STATUS / SHELF LIFE
-- ============================================================

CREATE TABLE IF NOT EXISTS inventory_statuses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    inventory_id UUID NOT NULL
        REFERENCES inventory(id) ON DELETE CASCADE,

    weather_snapshot_id UUID
        REFERENCES weather_snapshots(id) ON DELETE SET NULL,

    estimated_shelf_life_days NUMERIC,

    remaining_shelf_life_days NUMERIC,

    sell_by_date DATE,

    urgency TEXT,

    spoilage_risk TEXT,

    recommendation TEXT,

    factors JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS idx_inventory_statuses_inventory
    ON inventory_statuses(inventory_id);


CREATE INDEX IF NOT EXISTS idx_inventory_statuses_created
    ON inventory_statuses(created_at DESC);


-- ============================================================
-- 12. VENDOR EXTENSIONS
-- ============================================================
--
-- Existing `vendors` replaces AI doc's `buyer_profiles`.
-- Existing `vendor_requests` replaces `buyer_demands`.
--

ALTER TABLE vendors
    ADD COLUMN IF NOT EXISTS reliability_score NUMERIC DEFAULT 0,

    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();


ALTER TABLE vendor_requests
    ADD COLUMN IF NOT EXISTS fulfilled_at TIMESTAMPTZ,

    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();


-- ============================================================
-- 13. CROP PERFORMANCE HISTORY
-- ============================================================

CREATE TABLE IF NOT EXISTS crop_performance_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    farm_id UUID NOT NULL
        REFERENCES farms(id) ON DELETE CASCADE,

    field_id UUID
        REFERENCES field_area(id) ON DELETE SET NULL,

    crop TEXT NOT NULL,

    season TEXT,

    planted_date DATE,

    harvest_date DATE,

    yield_kg NUMERIC,

    revenue NUMERIC,

    cost NUMERIC,

    profit NUMERIC,

    weather_summary JSONB NOT NULL DEFAULT '{}'::jsonb,

    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS idx_crop_performance_farm
    ON crop_performance_history(farm_id);


CREATE INDEX IF NOT EXISTS idx_crop_performance_crop
    ON crop_performance_history(crop);


-- ============================================================
-- 14. CROP PLAN RECOMMENDATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS crop_plan_recommendations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    farm_id UUID NOT NULL
        REFERENCES farms(id) ON DELETE CASCADE,

    rank INTEGER NOT NULL,

    crop TEXT NOT NULL,

    expected_profit_per_kg NUMERIC,

    demand_outlook TEXT,

    waste_risk TEXT,

    planning_risk TEXT,

    recommendation TEXT,

    reason_labels JSONB NOT NULL DEFAULT '[]'::jsonb,

    suggested_crop_mix_pct INTEGER,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS idx_crop_plan_farm
    ON crop_plan_recommendations(farm_id);


CREATE INDEX IF NOT EXISTS idx_crop_plan_rank
    ON crop_plan_recommendations(farm_id, rank);


-- ============================================================
-- 15. SMART FARMING SUPERVISOR
-- ============================================================

CREATE TABLE IF NOT EXISTS smart_farming_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    farm_id UUID NOT NULL
        REFERENCES farms(id) ON DELETE CASCADE,

    field_id UUID
        REFERENCES field_area(id) ON DELETE SET NULL,

    agri_review_id UUID,

    business_review_id UUID,

    alerts JSONB NOT NULL DEFAULT '[]'::jsonb,

    next_actions JSONB NOT NULL DEFAULT '[]'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS idx_smart_reviews_farm
    ON smart_farming_reviews(farm_id);


-- ============================================================
-- 16. CHAT EXTENSIONS
-- ============================================================

ALTER TABLE chat_messages
    DROP CONSTRAINT IF EXISTS chat_messages_role_check;


ALTER TABLE chat_messages
    ADD CONSTRAINT chat_messages_role_check
    CHECK (
        role IN (
            'user',
            'assistant',
            'system'
        )
    );


ALTER TABLE chat_messages
    ADD COLUMN IF NOT EXISTS agent_context_json JSONB;


ALTER TABLE chat_sessions
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();


-- ============================================================
-- 17. NOTIFICATION EXTENSION
-- ============================================================

ALTER TABLE notifications
    ADD COLUMN IF NOT EXISTS farm_id UUID
        REFERENCES farms(id) ON DELETE CASCADE;


CREATE INDEX IF NOT EXISTS idx_notifications_farm
    ON notifications(farm_id);


-- ============================================================
-- 18. MODEL METADATA
-- ============================================================

CREATE TABLE IF NOT EXISTS ml_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT NOT NULL,

    source TEXT NOT NULL,

    model_type TEXT NOT NULL,

    model_path TEXT,

    labels_path TEXT,

    version TEXT NOT NULL,

    active BOOLEAN NOT NULL DEFAULT false,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS idx_ml_models_active
    ON ml_models(active);


-- ============================================================
-- 19. EXTEND YIELD FORECASTS
-- ============================================================

ALTER TABLE yield_forecasts
    ADD COLUMN IF NOT EXISTS field_id UUID
        REFERENCES field_area(id) ON DELETE SET NULL,

    ADD COLUMN IF NOT EXISTS model_name TEXT,

    ADD COLUMN IF NOT EXISTS model_version TEXT,

    ADD COLUMN IF NOT EXISTS risk_factors JSONB
        NOT NULL DEFAULT '[]'::jsonb;


-- ============================================================
-- 20. IMPACT METRICS EXTENSION
-- ============================================================

ALTER TABLE impact_metrics
    ADD COLUMN IF NOT EXISTS farm_id UUID
        REFERENCES farms(id) ON DELETE CASCADE,

    ADD COLUMN IF NOT EXISTS metadata JSONB
        NOT NULL DEFAULT '{}'::jsonb;


-- ============================================================
-- 21. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE weather_snapshots ENABLE ROW LEVEL SECURITY;

ALTER TABLE disease_diagnoses ENABLE ROW LEVEL SECURITY;

ALTER TABLE irrigation_decisions ENABLE ROW LEVEL SECURITY;

ALTER TABLE mqtt_commands ENABLE ROW LEVEL SECURITY;

ALTER TABLE inventory_statuses ENABLE ROW LEVEL SECURITY;

ALTER TABLE crop_performance_history ENABLE ROW LEVEL SECURITY;

ALTER TABLE crop_plan_recommendations ENABLE ROW LEVEL SECURITY;

ALTER TABLE smart_farming_reviews ENABLE ROW LEVEL SECURITY;

ALTER TABLE ml_models ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- WEATHER SNAPSHOTS
-- ============================================================

DROP POLICY IF EXISTS weather_snapshots_select
ON weather_snapshots;


CREATE POLICY weather_snapshots_select
ON weather_snapshots
FOR SELECT
USING (
    farm_id IN (
        SELECT id
        FROM farms
        WHERE farmer_id = public.farmer_id()
    )
);


-- ============================================================
-- DISEASE DIAGNOSES
-- ============================================================

DROP POLICY IF EXISTS disease_diagnoses_select
ON disease_diagnoses;


CREATE POLICY disease_diagnoses_select
ON disease_diagnoses
FOR SELECT
USING (
    farm_id IN (
        SELECT id
        FROM farms
        WHERE farmer_id = public.farmer_id()
    )
);


-- ============================================================
-- IRRIGATION DECISIONS
-- ============================================================

DROP POLICY IF EXISTS irrigation_decisions_select
ON irrigation_decisions;


CREATE POLICY irrigation_decisions_select
ON irrigation_decisions
FOR SELECT
USING (
    farm_id IN (
        SELECT id
        FROM farms
        WHERE farmer_id = public.farmer_id()
    )
);


-- ============================================================
-- MQTT COMMANDS
-- ============================================================
--
-- Client should generally not write these directly.
-- Backend/service role handles creation.
--

DROP POLICY IF EXISTS mqtt_commands_select
ON mqtt_commands;


CREATE POLICY mqtt_commands_select
ON mqtt_commands
FOR SELECT
USING (
    farm_id IN (
        SELECT id
        FROM farms
        WHERE farmer_id = public.farmer_id()
    )
);


-- ============================================================
-- INVENTORY STATUS
-- ============================================================

DROP POLICY IF EXISTS inventory_statuses_select
ON inventory_statuses;


CREATE POLICY inventory_statuses_select
ON inventory_statuses
FOR SELECT
USING (
    inventory_id IN (
        SELECT i.id
        FROM inventory i
        JOIN farms f
            ON f.id = i.farm_id
        WHERE f.farmer_id = public.farmer_id()
    )
);


-- ============================================================
-- CROP PERFORMANCE
-- ============================================================

DROP POLICY IF EXISTS crop_performance_select
ON crop_performance_history;


CREATE POLICY crop_performance_select
ON crop_performance_history
FOR SELECT
USING (
    farm_id IN (
        SELECT id
        FROM farms
        WHERE farmer_id = public.farmer_id()
    )
);


-- ============================================================
-- CROP PLAN RECOMMENDATIONS
-- ============================================================

DROP POLICY IF EXISTS crop_plan_recommendations_select
ON crop_plan_recommendations;


CREATE POLICY crop_plan_recommendations_select
ON crop_plan_recommendations
FOR SELECT
USING (
    farm_id IN (
        SELECT id
        FROM farms
        WHERE farmer_id = public.farmer_id()
    )
);


-- ============================================================
-- SMART FARMING REVIEWS
-- ============================================================

DROP POLICY IF EXISTS smart_farming_reviews_select
ON smart_farming_reviews;


CREATE POLICY smart_farming_reviews_select
ON smart_farming_reviews
FOR SELECT
USING (
    farm_id IN (
        SELECT id
        FROM farms
        WHERE farmer_id = public.farmer_id()
    )
);


-- ============================================================
-- ML MODELS
-- ============================================================
--
-- Model binaries are NOT stored in Postgres.
-- Only metadata is stored here.
--

DROP POLICY IF EXISTS ml_models_select
ON ml_models;


CREATE POLICY ml_models_select
ON ml_models
FOR SELECT
USING (true);


-- ============================================================
-- 22. SERVICE-ROLE INSERT / UPDATE NOTE
-- ============================================================
--
-- AI-agent writes should happen through the FastAPI backend using
-- the Supabase service-role client.
--
-- Do NOT expose service-role credentials to Flutter or ESP32.
--
-- ============================================================


COMMIT;
