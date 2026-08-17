# PROMPT — Frontend (Flutter)

Read `AGENTS.md` at the repo root first for shared conventions and the
full API surface (§7) this app is built against. This is a fresh
Flutter build — there's no existing frontend code to extend, so follow
this prompt directly, but always check `frontend/` for anything already
scaffolded before generating a file that might already exist.

Stack: Flutter (stable channel), Dart null-safety. State management:
Riverpod (`flutter_riverpod`) — pick one and be consistent, don't mix
Provider/Bloc/Riverpod. Backend access: `supabase_flutter` for auth +
storage + realtime, plain `http`/`dio` for the FastAPI backend.

---

## 1. Auth (OAuth)

Use `supabase_flutter`'s native OAuth:

```dart
await supabase.auth.signInWithOAuth(
  OAuthProvider.google,
  redirectTo: 'io.agritech.app://login-callback',
);
```

After the redirect completes, `supabase.auth.currentSession` has the
access token. Immediately call the backend's
`POST /auth/oauth/exchange` with that token. Use the response's
`is_new_user` flag to route:
- `true` → Onboarding flow (collect phone number, soil type, area
  locality — these map straight onto `PATCH /settings` and
  `PATCH /account`).
- `false` → Home.

Persist the session with `supabase_flutter`'s built-in local storage
(don't roll your own token storage). Every backend call attaches
`Authorization: Bearer <supabase access token>`.

Request the following permissions during onboarding, each with a
plain-language rationale screen before the OS prompt:
- **Notifications** (local + push) — for watering and match alerts.
- **Location** — only needed on the Market page's address prompt and
  for vendor distance calculations; ask for it there, not at launch.

---

## 2. Navigation shape

Bottom nav / drawer (your call, but be consistent) with these
top-level destinations, matching the design notes:

1. **Home** — dashboard/shortcuts
2. **Motor Control** — irrigation control for the active farm
3. **Market** — sell produce / view matches
4. **Upload** — photo + chat agent
5. **Recommendations** — next-season crop suggestions
6. **Settings**
7. **Account**

If a farmer has more than one farm, add a farm switcher at the top of
Home/Motor/Market/Recommendations (a simple dropdown backed by
`GET /farms`) rather than a separate page per farm.

---

## 3. Home page

Calls: `GET /motor/status?farm_id=`, `GET /notifications`,
`GET /account/water-saved`.

Sections:
- **Navbar/dashboard** — shortcuts to every other page.
- **Water saved till date** — big stat card from
  `/account/water-saved`.
- **LoRa signal strength** — small indicator using
  `motor_status.signal_strength` (now returned by the extended
  `/motor/status`, see `PROMPT_BACKEND.md` §3d). Show a bar/dBm value;
  gray it out if `null` (device never paired or hasn't reported yet).
- Recent unread notifications preview (top 3 from `/notifications`,
  link to a full notifications screen).

Push/local notification triggers (client-side scheduling is fine for
the "water time" reminder, but the actual `watering` and `match`
notification *content* comes from the backend's `/notifications` list
— poll it or, better, subscribe to the `notifications` table via
Supabase Realtime filtered on `farmer_id = auth.uid()` and show a local
notification when a new unread row arrives).

---

## 4. Motor Control page

Calls: `GET /motor/status`, `POST /motor/stop-current`,
`POST /motor/cancel-next`, `POST /motor/on`.

- **Last Watered** / **Next Watering Time** — from `motor_status.last_watered`
  / `.next_watering`.
- **Soil moisture graph** — plot `motor_status.moisture_readings`
  (already returned oldest→newest) as a simple time-series line chart
  (`fl_chart` or `syncfusion_flutter_charts`); label a "next water"
  marker at the estimated time if the current status is not already
  `running`.
- **Stop current watering** button → `POST /motor/stop-current`, only
  enabled when `current_status` is non-null (something is running).
- **Cancel next scheduled watering** button → `POST /motor/cancel-next`,
  only enabled when `next_watering` is non-null.
- **Manual motor ON** button → `POST /motor/on`. Disable it for a few
  seconds after tapping (optimistic UI) since the actual relay flip
  happens asynchronously via the hardware command-dispatch path.

---

## 5. Market page

Calls: `GET /market/address-prompt`, `POST /market/crop-match`,
`GET /market/requests`, `PATCH /market/{id}/extend-shelf-life`,
`PATCH /market/matches/{match_id}/confirm`.

Flow:
1. On first entry, call `/market/address-prompt`; if the farmer has no
   farm with a location set, prompt for their address (request
   location permission here, not at launch — reverse-geocode with the
   device's location if granted, or let them type it).
2. **Add crop match** form: crop name, shelf life (optional, days),
   harvested date (**mandatory**, date picker), expected price. Submit
   → `POST /market/crop-match`. Show returned `matches` inline the
   moment the response comes back — per design, results "must show the
   very moment when search button is pressed."
3. If no matches were found (`status == "open"`), keep the request
   visible in a "pending" list rather than discarding it — the backend
   keeps it valid until shelf life expiry, per design.
4. Each open/pending request needs an **Extend shelf life** action
   (numeric "additional days" input → `PATCH /market/{id}/extend-shelf-life`).
   Per design, the reminder notification for that request should stop
   appearing once extended — this is handled server-side (the backend
   deletes the stale `shelf_life_expiring` notification), so the
   frontend just needs to refresh its notification list after a
   successful extend call.
5. Each matched request needs a **Confirm sale** action on the specific
   match the farmer accepted → `PATCH /market/matches/{match_id}/confirm`.
   After confirming, remove/gray out any other matches for that same
   request in the UI (the backend also expires them server-side, but
   don't wait on a refetch to reflect it).

---

## 6. Upload page

Two modes in one screen (tabs or a toggle):

**A. Photo analysis** (existing backend flow):
`POST /upload/crop-image` (multipart, `farm_id` + file) →
`GET /upload/{id}/status` (poll every 2–3s until `analysis_status` is
`done`/`failed`). Show health status, detected diseases, and yield
estimate once ready.

**B. Chat agent**:
`POST /chat/sessions` (optionally with `farm_id`) once per
conversation, then `POST /chat/sessions/{id}/messages` for each turn.
Support attaching a photo to any message (same multipart pattern as A —
the backend stores it and gives the LLM the image context). Standard
chat UI: message bubbles, image thumbnails inline, loading indicator
while awaiting the assistant's reply.

---

## 7. Recommendations page

Calls: `GET /recommendations?farm_id=`.

Show three cards: **Health analysis**, **Yield analysis**, **Next
season recommendations** (crop list with confidence + reason, from
`next_season_recommendations.result_json.recommended_crops`), plus a
small chart of `yield_forecasts` over time if more than one point
exists.

---

## 8. Settings page

Calls: `GET /settings`, `PATCH /settings`.

Fields: preferred language (dropdown), soil type (dropdown — sandy /
loamy / clay / silty / peaty / chalky, or whatever taxonomy your soil
agent expects — confirm with backend before hardcoding), area locality
(text or a location picker), and the three notification toggles
(watering / match / system).

---

## 9. Account page

Calls: `GET /account`, `PATCH /account`.

Read-only OAuth details (name, email, avatar from the Supabase user
object) plus editable phone number. Show the `impact_metrics` list
returned by `/account` as a simple history/timeline (this is separate
from the Home page's single "water saved" stat — this is the fuller
metrics feed).

---

## 10. Vendor-side app (Market Vendors App)

Design calls this out as a distinct surface: vendors register, list
what they need, and set an expected price. Build this as a **second
Flutter entry point / flavor** within the same codebase (shared
design system, separate auth role) rather than a whole separate repo,
unless the team decides otherwise — confirm before duplicating the
whole app. Minimum screens:
- Vendor signup (`POST /vendors/signup`)
- "What I need" list + create form (`GET/POST /vendors/requests`)

---

## 11. Cross-cutting

- **Error handling**: every backend call can 401 (expired Supabase
  session) — on 401, refresh the Supabase session and retry once
  before forcing re-login.
- **Offline**: this is a farmer-facing rural app; assume flaky
  connectivity. Cache the last successful `/motor/status` and
  `/recommendations` response locally (e.g. `hive` or `shared_preferences`
  for simple cases) and show it with a "last updated" timestamp when a
  fresh fetch fails.
- **Multilingual support** is listed as a future feature — use
  `flutter_localizations` + `.arb` files from day one even with only
  English populated, so adding a language later is a translation task,
  not a refactor.
