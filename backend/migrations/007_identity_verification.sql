-- Identity verification and first-time onboarding
-- Run after the existing AgriTech migrations.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('FARMER', 'VENDOR', 'ADMIN');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'verification_status') THEN
        CREATE TYPE verification_status AS ENUM (
            'UNVERIFIED',
            'PHONE_VERIFIED',
            'IDENTITY_PENDING',
            'IDENTITY_VERIFIED',
            'IDENTITY_FAILED',
            'MANUAL_REVIEW',
            'SUSPENDED'
        );
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    role user_role NOT NULL,
    full_name TEXT,
    phone TEXT NOT NULL,
    state TEXT NOT NULL,
    district TEXT NOT NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    aadhaar_verified BOOLEAN NOT NULL DEFAULT FALSE,
    aadhaar_verified_at TIMESTAMPTZ,
    aadhaar_reference_id TEXT,
    aadhaar_last4 TEXT,
    verification_provider TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS identity_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    verification_type TEXT NOT NULL,
    provider TEXT NOT NULL,
    external_reference TEXT,
    masked_identifier TEXT,
    status verification_status NOT NULL DEFAULT 'IDENTITY_PENDING',
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    verified_at TIMESTAMPTZ,
    failure_reason TEXT,
    consent_given_at TIMESTAMPTZ,
    metadata JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS farmer_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    farmer_id TEXT NOT NULL,
    farmer_id_verified BOOLEAN NOT NULL DEFAULT FALSE,
    farmer_registry_state TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS vendor_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    business_name TEXT NOT NULL,
    contact_person TEXT,
    verification_type TEXT NOT NULL,
    registration_number TEXT NOT NULL,
    gstin TEXT,
    vendor_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS verification_otps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    purpose TEXT NOT NULL,
    recipient TEXT NOT NULL,
    otp_hash TEXT NOT NULL,
    salt TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    max_attempts INTEGER NOT NULL DEFAULT 5,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    consumed BOOLEAN NOT NULL DEFAULT FALSE,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS verification_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    status TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Demo data that documents the mock provider inputs without linking fake
-- identities to auth.users. These are not government verification records.
CREATE TABLE IF NOT EXISTS verification_demo_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_type TEXT NOT NULL,
    identifier TEXT NOT NULL,
    mobile TEXT NOT NULL,
    demo_otp TEXT NOT NULL,
    note TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_verification_demo_credentials_unique
    ON verification_demo_credentials(account_type, identifier);

INSERT INTO verification_demo_credentials (account_type, identifier, mobile, demo_otp, note)
VALUES
    ('FARMER', 'FARMER-DEMO-001', '9999999999', '123456', 'Mock Farmer Registry verification only. Not a government record.'),
    ('VENDOR', 'VENDOR-DEMO-001', '8888888888', '123456', 'Mock agricultural trader credential verification only. Not a government record.')
ON CONFLICT DO NOTHING;

CREATE UNIQUE INDEX IF NOT EXISTS idx_farmer_profiles_farmer_id_verified
    ON farmer_profiles (upper(farmer_id))
    WHERE farmer_id_verified = TRUE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_vendor_profiles_registration_verified
    ON vendor_profiles (verification_type, upper(registration_number))
    WHERE vendor_verified = TRUE;

CREATE INDEX IF NOT EXISTS idx_identity_verifications_user_id
    ON identity_verifications(user_id);

CREATE INDEX IF NOT EXISTS idx_identity_verifications_status
    ON identity_verifications(status);

CREATE INDEX IF NOT EXISTS idx_verification_otps_user_purpose
    ON verification_otps(user_id, purpose, consumed, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_verification_audit_logs_user_id
    ON verification_audit_logs(user_id, created_at DESC);

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE farmer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendor_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_otps ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_demo_credentials ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_profiles_own_read ON user_profiles;
CREATE POLICY user_profiles_own_read ON user_profiles
FOR SELECT USING (auth_user_id = auth.uid());

DROP POLICY IF EXISTS user_profiles_own_update ON user_profiles;
CREATE POLICY user_profiles_own_update ON user_profiles
FOR UPDATE USING (auth_user_id = auth.uid());

DROP POLICY IF EXISTS identity_verifications_own_read ON identity_verifications;
CREATE POLICY identity_verifications_own_read ON identity_verifications
FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS farmer_profiles_own_read ON farmer_profiles;
CREATE POLICY farmer_profiles_own_read ON farmer_profiles
FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS vendor_profiles_own_read ON vendor_profiles;
CREATE POLICY vendor_profiles_own_read ON vendor_profiles
FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS demo_credentials_read ON verification_demo_credentials;
CREATE POLICY demo_credentials_read ON verification_demo_credentials
FOR SELECT USING (true);

-- Service-role backend performs inserts/updates. Direct client inserts are
-- intentionally not exposed for OTP, audit, or verification state tables.
