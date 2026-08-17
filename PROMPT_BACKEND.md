# PROMPT — Backend (FastAPI + Supabase)

Read `AGENTS.md` at the repo root first for shared conventions and the
full target API surface. This prompt covers **only the delta** — the
backend scaffold at `backend/` already implements most of the design
(auth, farms, motor, market, upload, recommendations, settings,
account, notifications, webhooks, the 6 agent stubs, and the
APScheduler jobs). Read that existing code before writing anything —
match its style (async FastAPI routers, Pydantic v2 models, thin
routers that call into `services/` or `agents/`, Supabase client per
request via `get_supabase()` / `get_supabase_admin()`).

Stack: FastAPI (async), Pydantic v2, Supabase (Postgres + Auth +
Storage), APScheduler, httpx. Python 3.11+.

---

## 0. Prerequisite

Run `supabase/002_feature_gap_closure.sql` before writing any code
that touches the new tables it creates (`farm_devices`,
`hardware_status_events`, `vendors`, `vendor_requests`, `chat_sessions`,
`chat_messages`), or that relies on the widened `notifications.type`
constraint.

---

## 1. Fix the notification type bug

`app/routers/webhooks.py` inserts `type="agent_result"` and
`app/workers/scheduler.py` inserts `type="shelf_life_expiring"`. Once
migration 002 is applied this is no longer a DB error, but double check
no other code path inserts a `notifications.type` value outside the
widened CHECK list in the migration file. If you introduce a new
notification type, add it to that CHECK constraint too — don't just
insert and hope.

---

## 2. OAuth (replace/augment `app/routers/auth.py`)

The design calls for OAuth login (Google), not email/password as the
primary flow. Supabase handles the actual OAuth handshake — the mobile
app calls `supabase_flutter`'s `signInWithOAuth(OAuthProvider.google)`
directly against Supabase, and your backend never sees the user's
Google credentials. What the backend needs to do:

- Keep `/auth/signup` and `/auth/login` for testing/admin tooling, but
  they are no longer the primary flow.
- Add `POST /auth/oauth/exchange`: the Flutter app sends the Supabase
  access token it already obtained via OAuth; the backend verifies it
  with `decode_jwt` (already exists) and, **if no `farmers` row exists
  yet for that `sub`**, creates one using `name`/`email`/`avatar_url`
  claims from the Supabase user object (call
  `sb.auth.get_user(token)` with the anon client to fetch those). This
  makes signup and login the same call for OAuth users — there's no
  separate "register" step.
- Response shape: reuse `FarmerProfile` from `app/models/farmer.py`,
  plus `is_new_user: bool` so the Flutter app knows whether to route to
  an onboarding screen (asking for phone number, soil type, locality).

```python
class OAuthExchangeRequest(BaseModel):
    access_token: str

class OAuthExchangeResponse(BaseModel):
    profile: FarmerProfile
    is_new_user: bool
```

---

## 3. Hardware pairing + command dispatch + status feedback

This closes gap #4/#5 from `AGENTS.md` §3 — today the scheduler flips a
DB row to `running` but nothing actually talks to the ESP32, and there's
no way for the ESP32 to report back.

### 3a. Pairing — `POST /farms/{farm_id}/devices`

Body: `{ "device_uid": "<esp32 chip id>", "device_secret": "<random secret shown once during ESP32 provisioning>" }`.
Hash `device_secret` (e.g. `hashlib.sha256`) and store it as
`device_secret_hash` in `farm_devices`. Return the created row (without
the hash). This is called once from the Flutter app during device
setup, authenticated as the farmer.

### 3b. Command dispatch — `POST /motor/dispatch` (internal)

Not exposed to the Flutter app directly — called by `/motor/on` and by
the scheduler's `check_irrigation_schedule` job instead of just
updating the DB row. Looks up the farm's `farm_devices` row, and POSTs
a signed command to wherever the ESP32 polls from or is reachable at
(see `PROMPT_IOT.md` for the transport — MVP is HTTP long-poll from the
ESP32 to a `GET /motor/pending-command?device_uid=...` endpoint you'll
also need to add, since ESP32 behind NAT usually can't accept inbound
connections). Sign the command with `HARDWARE_COMMAND_SECRET` using the
same HMAC pattern as `verify_agent_webhook` in `security.py` — don't
invent a new scheme.

Add:
```
GET /motor/pending-command?device_uid=...
```
Returns the next queued command (`{"action": "on"|"off", "issued_at": ...}`)
for that device, or `204 No Content` if none. The ESP32 polls this
every N seconds (see IoT prompt).

### 3c. Status feedback — `POST /webhooks/hardware-status`

Auth: reuse `verify_agent_webhook` (same shared-secret / HMAC scheme,
different secret — `HARDWARE_COMMAND_SECRET` instead of
`AGENT_WEBHOOK_SECRET`; consider parameterizing `verify_agent_webhook`
to accept which secret to check rather than duplicating it).

Body:
```python
class HardwareStatusPayload(BaseModel):
    device_uid: str
    event_type: str  # heartbeat | motor_on | motor_off | error
    signal_strength: int | None = None
    payload: dict = {}
```

On receipt: upsert `farm_devices.last_signal_strength`,
`last_seen_at`, and `motor_relay_state`; insert a row into
`hardware_status_events`; if `event_type == "error"`, create a
`system`-type notification for the owning farmer.

### 3d. Extend `GET /motor/status`

Join in the paired `farm_devices` row for that farm and include
`signal_strength` and `motor_relay_state` in the response, so the
Flutter Home page can show LoRa signal strength without a second call.

---

## 4. Settings: soil type + area locality

`app/routers/settings.py`'s `SettingsUpdate` model and both handlers
currently only touch `preferred_language`. Extend:

```python
class SettingsUpdate(BaseModel):
    preferred_language: str | None = None
    soil_type: str | None = None
    area_locality: str | None = None
    notification_watering: bool | None = None
    notification_match: bool | None = None
    notification_system: bool | None = None
```

`GET /settings` and `PATCH /settings` should read/write
`farmers.soil_type` / `farmers.area_locality` (added by migration 002)
the same way `preferred_language` is handled today. The
`notification_*` booleans are still not backed by a table in this
scaffold — either add a `notification_prefs JSONB` column on `farmers`
in a follow-up migration, or keep them as accepted-but-not-yet-persisted
fields and say so in the response; don't silently drop them.

---

## 5. Confirm-sale endpoint

`rescue_matches.status` already supports `'confirmed'` but nothing sets
it. Add to `app/routers/market.py`:

```
PATCH /market/matches/{match_id}/confirm
```

- Verify the match belongs to a `demand_request` (or `vendor_request`,
  once vendors exist) owned by the current farmer/vendor.
- Set `status = 'confirmed'`, `confirmed_at = now()`.
- Set the parent `demand_requests.status` (or `vendor_requests.status`)
  to `'matched'` if not already, and reject/expire any *other*
  `rescue_matches` rows tied to the same parent request so the listing
  stops surfacing elsewhere (design: "vendors or buyers won't see match
  option in future where it is not needed").
- Fire a `sale_confirmed` notification to the counter-party.

---

## 6. Vendor marketplace

New router `app/routers/vendors.py`:

```
POST /vendors/signup        -- creates a vendors row for the current auth.uid()
GET  /vendors/requests      -- list the vendor's own vendor_requests
POST /vendors/requests      -- create a vendor_request {crop_name, quantity_needed, expected_price}
```

Reuse `get_current_farmer`-style JWT auth (rename/generalize to
`get_current_user` if it's cleaner, since the same JWT now identifies
either a farmer or a vendor — check which table has a row for that
`sub` to disambiguate, or add a `role` claim).

Extend `app/agents/demand_matching.py`'s real (non-stub) implementation
later to also match against open `vendor_requests`, not just its own
mocked buyer. For now, keep the stub but note in its docstring that it
should eventually query both `vendor_requests` and any external
buyer/market feed.

---

## 7. Chat / photo-Q&A agent

New router `app/routers/chat.py`:

```
POST /chat/sessions                       -- {farm_id?: str} -> creates chat_sessions row, returns id
POST /chat/sessions/{id}/messages         -- multipart: {content?: str, image?: file}
```

On a new message: insert the user's `chat_messages` row (uploading any
image to Supabase Storage first, same bucket pattern as
`upload/crop-image`), then call an LLM (env vars `LLM_API_KEY` /
`LLM_API_BASE_URL` from `AGENTS.md` §6) with the running message
history for that session — include the farm's latest soil-moisture,
health, and inventory data as system context if `farm_id` is set, so
the farmer can ask things like "why did my irrigation skip yesterday?"
and get a grounded answer. Insert the assistant's reply as a
`chat_messages` row and return it.

Keep this behind a thin `agents/chat_agent.py` module (new file,
matches the existing `agents/` pattern) with a single
`async def answer(session_id: str, farm_context: dict) -> str`
function, so the LLM call is swappable like every other agent.

---

## 8. Water-saved endpoint

```
GET /account/water-saved
```

`SELECT total_water_saved_liters FROM farmer_water_saved_totals WHERE farmer_id = :id`
(the view is created by migration 002). Return `{"total_water_saved_liters": 0}`
if no row exists yet. Whichever code path decides an irrigation cycle
was skipped because soil moisture was already adequate (soil-moisture
agent's "optimal"/"adequate" branches) should insert a row into
`impact_metrics` with `metric_type='water_saved_liters'` and an
estimated liters value — wire that in wherever `analyze_moisture()`'s
result is consumed by the scheduler.

---

## 9. Tests

Follow the existing pattern in `tests/test_market_and_motor.py` (a
hand-rolled `MockClient`/`MockTable` rather than hitting real Supabase).
Every new endpoint above needs at least one happy-path test using that
same mock. Don't introduce a second mocking approach.

---

## 10. requirements.txt / .env.example

Add to `requirements.txt` only if you actually use them:
- an LLM SDK (or just `httpx`, which is already a dependency, if you
  call the LLM API directly)

Add every new env var from `AGENTS.md` §6 to `.env.example` as you
introduce it in `config.py`. Never hardcode a secret.
