# Identity Verification Onboarding

## Existing Auth Architecture

AgriTech uses Supabase Auth as the source of truth. The FastAPI backend verifies Supabase JWTs in `app/core/security.py` and existing signup/login routes live in `app/routers/auth.py`. Farmer profile data is stored in `farmers`; vendor profile data is stored in `vendors`. This implementation keeps those tables and adds a verification layer around them.

## Modified Files

- `backend/app/routers/auth.py`: added `/auth/signup/start` and verification metadata in `/auth/me`.
- `backend/app/main.py`: includes the verification router.
- `backend/app/routers/market.py`: requires `VERIFIED_FARMER` for produce publishing.
- `backend/app/routers/vendors.py`: requires `VERIFIED_VENDOR` for commercial vendor actions.
- `backend/app/agents/demand_matching.py`: adds verified vendor signal to buyer scoring metadata.
- `backend/app/core/config.py`, `backend/.env.example`: identity provider and OTP settings.
- `frontend/lib/providers/providers.dart`: added `needsVerification` auth state.
- `frontend/lib/services/backend.dart`: added verification API calls.
- `frontend/lib/models/models.dart`: added verification status/badge models.
- `frontend/lib/app.dart`, `frontend/lib/screens/auth/login_screen.dart`, `frontend/lib/screens/home/home_screen.dart`, `frontend/lib/screens/vendor/vendor_home_screen.dart`: verification signup and badges.

## New Files

- `backend/app/models/verification.py`
- `backend/app/services/identity_providers.py`
- `backend/app/services/identity_verification_service.py`
- `backend/app/routers/verification.py`
- `backend/migrations/007_identity_verification.sql`
- `backend/tests/test_identity_verification.py`
- `frontend/lib/screens/auth/identity_onboarding_screen.dart`

## Database Migration

Run `backend/migrations/007_identity_verification.sql`. It creates:

- `user_profiles`
- `identity_verifications`
- `farmer_profiles`
- `vendor_profiles`
- `verification_otps`
- `verification_audit_logs`
- `verification_demo_credentials`

Demo credentials:

- Farmer: `FARMER-DEMO-001`, mobile `9999999999`, OTP `123456`
- Vendor: `VENDOR-DEMO-001`, mobile `8888888888`, OTP `123456`

## Provider Architecture

```text
Flutter Signup
  -> FastAPI Verification API
  -> Identity Verification Service
  -> FarmerIdentityProvider / VendorIdentityProvider / AadhaarVerificationProvider
  -> Supabase verification tables
  -> Verified badge and marketplace permissions
```

Mock providers are used only when `IDENTITY_PROVIDER_MODE=mock`. Production placeholders return `NOT_CONFIGURED` until an authorized registry, trader credential, or Aadhaar AUA/KUA/ASA provider is integrated.

## API Examples

```http
POST /auth/signup/start
{
  "email": "farmer@example.com",
  "password": "secret123",
  "role": "FARMER",
  "full_name": "Demo Farmer",
  "phone": "9999999999",
  "state": "Tamil Nadu",
  "district": "Chennai",
  "consent": true
}
```

```http
POST /verification/farmer/start
{
  "full_name": "Demo Farmer",
  "mobile_number": "9999999999",
  "state": "Tamil Nadu",
  "district": "Chennai",
  "farmer_id": "FARMER-DEMO-001",
  "consent": true
}
```

```http
POST /verification/vendor/verify
{
  "verification_type": "ENAM_TRADER",
  "registration_number": "VENDOR-DEMO-001",
  "mobile_number": "8888888888",
  "otp": "123456"
}
```

```http
GET /verification/status
```

Response includes `verification_status`, `badge`, `phone_verified`, `farmer_id_verified`, `vendor_verified`, `aadhaar_verified`, and `demo_mode`.

## Signup Sequence

```text
User selects Farmer or Vendor
  -> /auth/signup/start creates Supabase user + user_profiles row
  -> /auth/phone/send-otp
  -> /auth/phone/verify-otp
  -> Farmer: /verification/farmer/start -> /send-otp -> /verify
  -> Vendor: /verification/vendor/start -> /send-otp -> /verify
  -> Optional: /verification/aadhaar/request-otp -> /verify-otp
  -> /verification/status returns VERIFIED_FARMER or VERIFIED_VENDOR badge
  -> marketplace write actions are unlocked
```

## Security And Privacy Decisions

- Supabase JWT remains the authentication boundary.
- Verification is server-side only; Flutter never stores provider secrets.
- OTPs are stored only as HMAC hashes with salt, expiry, attempt limit, consumed flag, and audit events.
- Aadhaar OTP, full Aadhaar number, provider secrets, access tokens, and raw Aadhaar payloads are never stored or logged.
- Aadhaar storage is limited to `aadhaar_verified`, `aadhaar_verified_at`, `aadhaar_reference_id`, `aadhaar_last4`, and provider name.
- Duplicate verified Farmer IDs and verified vendor registrations are blocked by partial unique indexes.
- Marketplace commercial actions require `IDENTITY_VERIFIED` with the correct role.
- Mock mode is explicit in API responses and UI and must not be represented as government verification.
