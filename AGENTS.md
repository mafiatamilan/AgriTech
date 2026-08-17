# AGENTS.md — AgriTech (Phoenix Hacks)

This file is the entry point for any human or AI agent working on this repo.
Read this file fully before touching any code. Then jump to the domain
prompt that matches your task:

| Domain | Prompt file | When to use it |
|---|---|---|
| Backend (FastAPI + Supabase) | `prompts/PROMPT_BACKEND.md` | Adding/changing API routes, agents, DB access, webhooks, scheduler jobs |
| Frontend (Flutter) | `prompts/PROMPT_FRONTEND.md` | Building the farmer/vendor mobile app UI |
| IoT / Firmware (ESP32 + LoRa) | `prompts/PROMPT_IOT.md` | Arduino/ESP32 firmware for soil sensors and motor relay control |
| Database | `supabase/002_feature_gap_closure.sql` | Run once against Supabase, after `backend/migrations/001_initial_schema.sql` |

Do not regenerate a whole domain from scratch. The backend already has a
working scaffold at `backend/`. Read the existing code in the relevant
directory first, then extend it — do not duplicate routers, models, or
tables that already exist.

---

## 1. What this project is

AgriTech is a multi-agent AI system for smallholder farmers that:
- Automates irrigation using soil-moisture + weather data (ESP32 + LoRa + relay + pump)
- Detects crop disease from photos and predicts yield
- Tracks harvested inventory and matches it with nearby buyers/vendors before it spoils
- Recommends next season's crops based on past yield/profit/weather

Full context (personas, pain points, architecture diagram) is in the
original pitch deck; the important thing for implementation is the six
agents and the data they read/write, listed in section 4.

---

## 2. Repo layout (target state)

```
AgriTech/
├── AGENTS.md                      # this file
├── prompts/
│   ├── PROMPT_BACKEND.md
│   ├── PROMPT_FRONTEND.md
│   └── PROMPT_IOT.md
├── supabase/
│   └── 002_feature_gap_closure.sql
├── backend/                       # already exists — FastAPI, see PROMPT_BACKEND.md
│   ├── app/
│   │   ├── main.py
│   │   ├── core/                  # config, security (JWT + agent webhook HMAC), deps
│   │   ├── db/                    # supabase_client.py
│   │   ├── models/                # pydantic schemas
│   │   ├── routers/               # auth, farms, motor, market, upload, recommendations,
│   │   │                          # settings, account, notifications, webhooks
│   │   ├── agents/                # 6 stub agents — see section 4
│   │   ├── services/               # irrigation_service, notification_service
│   │   └── workers/                # apscheduler jobs
│   ├── migrations/001_initial_schema.sql
│   └── tests/
├── frontend/                      # new — Flutter app, see PROMPT_FRONTEND.md
└── iot/                           # new — ESP32 firmware, see PROMPT_IOT.md
```

---

## 3. Known gaps between the design plan and the current backend

These were found by diffing the pitch-deck design plan and the Flutter/
backend feature notes against the code at
`github.com/mafiatamilan/AgriTech` (branch `feature/backend-scaffold`).
Fix these as part of backend work; the frontend and IoT prompts assume
they've been fixed.

1. **Notification `type` CHECK constraint is too narrow.** The DB only
   allows `('watering','match','system')`, but `webhooks.py` inserts
   `'agent_result'` and `scheduler.py` inserts `'shelf_life_expiring'` —
   both currently violate the constraint and will throw at runtime.
   Fixed by `supabase/002_feature_gap_closure.sql`.
2. **Auth is email/password, design wants OAuth.** `auth.py` only wraps
   `sb.auth.sign_up` / `sign_in_with_password`. The Flutter app needs
   Supabase's native OAuth flow (Google Sign-In) instead — see
   `PROMPT_BACKEND.md` §OAuth and `PROMPT_FRONTEND.md` §Auth.
3. **No vendor-side marketplace.** The design's "Market Vendors App"
   lets a vendor post what they need and set an expected price; the
   scaffold only has farmer-initiated `demand_requests`. New tables
   `vendors` / `vendor_requests` and matching endpoints are needed.
4. **No hardware command dispatch or status feedback loop.** The
   scheduler flips `irrigation_events.status` to `running` but never
   actually sends a command down to the ESP32, and there's no endpoint
   for the ESP32 to report signal strength / motor state / errors back
   up. New `farm_devices` + `hardware_status_events` tables and two new
   endpoints close this gap.
5. **No device pairing.** Nothing links a `farm_id` to a specific
   ESP32/LoRa unit. Needed for the previous point to be secure.
6. **Settings page fields don't exist in the DB.** "Type of soil" and
   "Area locality" are on the Flutter settings screen but have no
   backing columns.
7. **No "confirm sale" endpoint.** `rescue_matches.status` already
   supports `'confirmed'`, but nothing sets it. Design requires this so
   a completed sale stops appearing as an open match to other buyers.
8. **No LoRa signal-strength field** for the Home page's "signal
   strength" indicator.
9. **No interactive chat / photo-Q&A endpoint.** The Upload page wants
   a simple chat interface backed by an AI agent, plus photo upload
   with free-form questions. Only static crop-image analysis exists
   today.

All of the above are addressed by `supabase/002_feature_gap_closure.sql`
plus the new endpoints specified in `PROMPT_BACKEND.md`.

---

## 4. The six agents (contract, not implementation)

Every agent below already has a stub at `backend/app/agents/*.py` that
returns realistic mock JSON. Treat the function signature and return
shape as the contract — swap the internals for a real model without
changing callers.

| Agent | File | Input | Output (JSON shape) |
|---|---|---|---|
| Soil Moisture | `soil_moisture.py` | list of `{moisture_pct, recorded_at}` | `{moisture_pct, hours_to_next_water, status}` |
| Crop Health / Disease | `crop_health.py` | image URL | `{health_status, diseases_detected[], confidence, recommendations}` |
| Yield Prediction | `yield_prediction.py` | image URL + sensor history | `{expected_yield_kg, confidence, crop_type}` |
| Inventory | `inventory_agent.py` | farm_id, crop_name, quantity, harvested_date | `{crop_name, quantity, status, low_stock_alert}` |
| Demand Matching | `demand_matching.py` | a `demand_requests` row | `list[{buyer_name, offered_price, distance_km, shelf_life_compatible, match_score}]` |
| Next Season | `next_season.py` | farm_id + historical data | `{recommended_crops[], planting_window, soil_preparation}` |

When wiring a real model in, keep everything async and keep the
`"note": "stub — replace with real ..."` field removed once it's real,
so it's obvious from the response which agents are still stubbed during
demos.

---

## 5. Shared conventions (apply to every domain)

- **Auth**: Supabase Auth (Postgres `auth.users`) is the source of
  truth. The `farmers.id` and `vendors.id` PKs are foreign keys into
  `auth.users(id)`. The backend verifies the Supabase JWT itself
  (`app/core/security.py::decode_jwt`) rather than trusting a client
  claim — don't change that pattern.
- **Row Level Security is mandatory.** Every table holding
  farmer/vendor data has RLS policies keyed off `auth.uid()`
  (`auth.farmer_id()` helper). Any new table needs equivalent policies —
  see `supabase/002_feature_gap_closure.sql` for the pattern.
- **Hardware webhook auth** uses either a shared secret header
  (`X-Agent-Secret`) or an HMAC signature (`X-Signature` +
  `X-Timestamp`), see `verify_agent_webhook` in `security.py`. Reuse
  this for any new inbound hardware/agent webhook rather than inventing
  a new auth scheme.
- **Never commit secrets.** `.env` is gitignored; `.env.example` lists
  every required variable. Add new variables to `.env.example` whenever
  you add one to `config.py`.
- **All agent functions and route handlers are `async`.**
- **IDs are UUIDs everywhere** (Postgres `gen_random_uuid()` default).
- **Timestamps** are `TIMESTAMPTZ`, always UTC, ISO-8601 over the wire.

---

## 6. Environment variables (master list)

```
# Supabase
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_JWT_SECRET=

# Direct Postgres (migrations)
DATABASE_URL=

# Agent / webhook auth
AGENT_WEBHOOK_SECRET=
AGENT_DISPATCH_URL=

# Hardware command dispatch (new — see PROMPT_BACKEND.md)
HARDWARE_COMMAND_SECRET=

# External APIs
WEATHER_API_KEY=
WEATHER_API_BASE_URL=

# LLM (chat agent + any real model calls)
LLM_API_KEY=
LLM_API_BASE_URL=
```

---

## 7. Full API surface (target state — existing + new)

Endpoints already implemented are unmarked; new ones needed to close
the gaps in §3 are marked **NEW**.

| Method | Path | Purpose |
|---|---|---|
| POST | /auth/signup | Email/password signup (kept for testing) |
| POST | /auth/login | Email/password login (kept for testing) |
| **NEW** POST | /auth/oauth/exchange | Exchange a Supabase OAuth session for the app's session (see PROMPT_BACKEND §OAuth) |
| GET | /auth/me | Current farmer profile |
| GET | /farms | List farms |
| POST | /farms | Create farm |
| GET | /farms/{id} | Get farm |
| PATCH | /farms/{id} | Update farm |
| **NEW** POST | /farms/{id}/devices | Pair an ESP32/LoRa device to a farm |
| **NEW** POST | /webhooks/hardware-status | ESP32 → cloud status/heartbeat feedback |
| **NEW** POST | /motor/dispatch | Actually send an irrigation command downstream (called internally by the scheduler and by /motor/on) |
| GET | /motor/status | Irrigation status + moisture graph + signal strength |
| POST | /motor/stop-current | Stop running irrigation |
| POST | /motor/cancel-next | Cancel next scheduled watering |
| POST | /motor/on | Manual motor on |
| POST | /market/crop-match | Farmer lists produce, gets matched with buyers |
| GET | /market/requests | List farmer's demand requests |
| PATCH | /market/{id}/extend-shelf-life | Extend shelf life, re-run matching |
| **NEW** PATCH | /market/matches/{match_id}/confirm | Mark a match as a confirmed sale |
| **NEW** POST | /vendors/signup | Register a vendor account |
| **NEW** POST | /vendors/requests | Vendor posts what they need + expected price |
| **NEW** GET | /vendors/requests | List a vendor's own requests |
| POST | /upload/crop-image | Upload crop photo, dispatch health + yield agents |
| GET | /upload/{id}/status | Analysis status/results |
| **NEW** POST | /chat/sessions | Start a chat session (optionally with an image) |
| **NEW** POST | /chat/sessions/{id}/messages | Send a message / photo question, get agent reply |
| GET | /recommendations | Health/yield/next-season summary for a farm |
| GET | /settings | Get settings (incl. soil_type, area_locality) |
| PATCH | /settings | Update settings |
| GET | /account | Account info + impact metrics |
| PATCH | /account | Update account |
| **NEW** GET | /account/water-saved | Total water saved to date (Home page stat) |
| GET | /notifications | List notifications |
| PATCH | /notifications/{id}/read | Mark as read |
| POST | /webhooks/agent-result | AI agent → cloud result callback |

---

## 8. Order of work for a fresh agent picking this up

1. Run `supabase/002_feature_gap_closure.sql` against the Supabase
   project (after confirming `001_initial_schema.sql` is already applied).
2. Read `prompts/PROMPT_BACKEND.md` and implement the **NEW** endpoints
   in §7 above, on top of the existing scaffold.
3. Read `prompts/PROMPT_IOT.md` and build the ESP32 firmware against
   the new pairing + status-webhook + command-dispatch endpoints.
4. Read `prompts/PROMPT_FRONTEND.md` and build the Flutter app against
   the full endpoint list in §7.
5. Wire real models into the six agents in `backend/app/agents/`,
   replacing the stubs one at a time, without changing their function
   signatures.
