-- ============================================================
-- AgriTech — Migration 005: Irrigation Configuration
--
-- RUN AFTER:
--   001_initial_schema.sql
--   002_updated.sql
--   003_updated.sql
--   004_ai_agent_run_impact.sql
--
-- Adds the farmer-configured pump flow rate to field_area so the
-- irrigation agent can compute physically meaningful runtimes:
--
--     water_volume_liters = water_depth_mm * area_m2   (1 mm over 1 m² = 1 L)
--     duration_minutes    = water_volume_liters / pump_flow_lpm
--
-- No duplicate columns are created: field_area already has
-- area_size / crop_type / planted_date / soil_type / growth_stage.
-- ============================================================

BEGIN;

-- Farmer-configured pump delivery rate (litres per minute).
-- NULL = legacy/unknown; the irrigation agent falls back to a
-- documented estimate and says so in its reasoning.
ALTER TABLE field_area
    ADD COLUMN IF NOT EXISTS pump_flow_lpm NUMERIC;

-- Positive-value validation, safe for NULL (legacy rows).
ALTER TABLE field_area
    DROP CONSTRAINT IF EXISTS field_area_pump_flow_lpm_positive;

ALTER TABLE field_area
    ADD CONSTRAINT field_area_pump_flow_lpm_positive
    CHECK (pump_flow_lpm IS NULL OR pump_flow_lpm > 0);

COMMIT;