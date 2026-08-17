# AgriTech — Flutter frontend

Farmer app (`lib/main.dart`) and a lighter vendor app (`lib/main_vendor.dart`)
sharing the same auth, theme, models, and API layer.

## Run

Dart defines are injected at build/run time — no `.env` file.

```sh
flutter pub get

# Farmer app
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key

# Vendor app (same defines)
flutter run -t lib/main_vendor.dart
```

| Define | Default | Notes |
|---|---|---|
| `API_BASE_URL` | `http://localhost:8000` | Use `10.0.2.2` on the Android emulator. |
| `SUPABASE_URL` | (none — required) | Must match the backend's Supabase project. |
| `SUPABASE_ANON_KEY` | (none — required) | |
| `DEEP_LINK_SCHEME` | `io.agritech.app` | Custom scheme for the OAuth callback. |

`AppConfig` lives in `lib/core/config.dart`.

## Auth (Google OAuth)

The app starts the Supabase Google OAuth flow
(`Supabase.initialize(publishableKey: ...)`, `signInWithOAuth` with
`redirectTo: io.agritech.app://login-callback`), then calls the backend's
`POST /auth/oauth/exchange` to create/load the farmer profile and mark
onboarding complete.

Deep link already configured:

- **Android** — `android/app/src/main/AndroidManifest.xml` has a VIEW
  intent-filter for scheme `io.agritech.app`.
- **iOS** — `ios/Runner/Info.plist` has a `CFBundleURLTypes` entry for the same
  scheme.

On iOS, also whitelist the custom scheme in
`ios/Runner/Info.plist` under `LSApplicationQueriesSchemes` if you later need
to detect the handler. No Google client-side configuration is needed — the
OAuth provider is configured on the Supabase side.

## Offline behavior

Two pages degrade gracefully when the backend is unreachable:

- **Motor status** — last successful `/motor/status` payload is cached per
  farm (`CacheStore`, shared_preferences). The UI shows a "stale" banner with
  the cache time.
- **Recommendations** — same pattern for `/recommendations`.

Everything else shows the API error inline; mutations require connectivity.

## Structure

```
lib/
  main.dart / main_vendor.dart   # entry points
  core/          # config, supabase client, http client (Bearer + 401 retry), theme
  services/      # supabase_service, backend (API), cache
  models/        # typed API response models
  providers/     # riverpod providers + realtime notifications counter
  screens/       # auth, home, motor, market, upload, recommendations, settings, account, notifications, vendor
  widgets/       # shared widgets + moisture/yield charts
  l10n/          # generated from app_en.arb
```

## Known backend gap

`GET /market/requests` does not embed `rescue_matches` in its rows. The Market
page is ready to show a **Confirm sale** button per embedded match, but the
button only renders once the backend starts including `matches` in the
response. See AGENTS.md §3 item 7.