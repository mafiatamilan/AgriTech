# PROMPT — IoT / Firmware (ESP32 + LoRa Irrigation Controller)

Read `AGENTS.md` at the repo root first. This covers the hardware side
of the design's "Hardware Architecture (Irrigation Control)" diagram:

```
Home/Cloud Server <--Internet--> ESP32 (Controller) --LoRa A (TX)-->
LoRa A (RX) --wired--> Relay Module --> Motor/Pump
```

Two physical units:
- **Controller unit**: ESP32 + LoRa transmitter, has internet access
  (WiFi), talks to the backend.
- **Relay unit**: LoRa receiver + relay module + motor/pump, out in the
  field where WiFi doesn't reach, talks only over LoRa to the
  controller unit.

Toolchain: Arduino IDE or PlatformIO (prefer PlatformIO — reproducible
builds via `platformio.ini`), C++. LoRa library: `RadioLib` or
`LoRa` (Sandeep Mistry) depending on the radio module (SX127x family
assumed — confirm actual hardware before locking a library).

---

## 1. Repo layout

```
iot/
├── platformio.ini
├── controller/          # ESP32 + LoRa TX firmware
│   └── src/main.cpp
├── relay_unit/          # ESP32 (or lower-power MCU) + LoRa RX + relay
│   └── src/main.cpp
└── shared/
    └── lora_protocol.h  # shared command/status packet definitions
```

---

## 2. LoRa packet protocol (`shared/lora_protocol.h`)

Keep packets tiny — LoRa airtime is precious. Use a fixed-size struct,
not JSON, over the air:

```cpp
// Controller -> Relay
struct LoraCommand {
    uint8_t  type;        // 0 = motor_on, 1 = motor_off, 2 = ping
    uint32_t command_id;  // monotonically increasing, for dedup/ack matching
};

// Relay -> Controller
struct LoraStatus {
    uint8_t  type;        // 0 = ack, 1 = heartbeat, 2 = error
    uint32_t command_id;  // echoes the command being acked, or 0 for unsolicited heartbeat
    uint8_t  relay_state; // 0 = off, 1 = on
    int8_t   rssi;        // signal strength as seen by the relay unit
};
```

Both units run a light send/retry loop: controller retries a command up
to 3 times with a short backoff if no matching `ack` arrives; relay
sends an unsolicited `heartbeat` every 60s regardless of commands so
the controller (and therefore the backend) can detect a dead relay unit.

---

## 3. Controller unit firmware (`controller/src/main.cpp`)

Responsibilities:
1. Connect to WiFi (store SSID/password in `platformio.ini` build flags
   or, better, via a captive-portal provisioning flow using
   `WiFiManager` so this isn't hardcoded per-unit).
2. **Pairing**: on first boot (no stored `device_secret`), generate a
   random secret, display/print it (e.g. over serial, or a simple
   local web page via `WiFiManager`'s portal) so it can be entered into
   the Flutter app's device-pairing screen, which calls
   `POST /farms/{farm_id}/devices` with this ESP32's chip ID
   (`ESP.getEfuseMac()` on ESP32) as `device_uid` and the generated
   secret. Store the secret in NVS (`Preferences` library) after
   confirming the pairing call succeeded.
3. **Poll for commands**: every ~10s, `GET /motor/pending-command?device_uid=...`
   with the pairing secret in the `X-Agent-Secret` header (matches the
   backend's `verify_agent_webhook` shared-secret path — see
   `PROMPT_BACKEND.md` §3c). On `200`, parse the JSON action and send
   the corresponding `LoraCommand` to the relay unit. On `204`, do
   nothing.
4. **Relay LoRa status uplink**: whenever a `LoraStatus` packet arrives
   from the relay unit (ack, heartbeat, or error), POST it to
   `POST /webhooks/hardware-status` with the same `X-Agent-Secret`
   header, body:
   ```json
   {"device_uid": "...", "event_type": "heartbeat|motor_on|motor_off|error",
    "signal_strength": -72, "payload": {"relay_state": 1}}
   ```
5. **Local safety timeout**: if the relay unit hasn't sent a heartbeat
   in 3 consecutive expected intervals, treat it as offline — report an
   `error` event and, if the last known relay state was `on`, keep
   retrying an `motor_off` command aggressively (fail-safe: prefer a
   pump stuck off over a pump stuck on when comms are flaky).

---

## 4. Relay unit firmware (`relay_unit/src/main.cpp`)

Responsibilities:
1. Listen continuously on LoRa for `LoraCommand` packets addressed to
   its paired controller (simplest MVP: single controller per relay
   unit, no addressing needed beyond the LoRa channel/sync word).
2. On `motor_on`/`motor_off`: drive the relay GPIO pin accordingly,
   then send back a `LoraStatus{type: ack, command_id: <echoed>,
   relay_state: <new state>, rssi: <RSSI of the command packet just received>}`.
3. Send an unsolicited `heartbeat` status every 60s with current
   `relay_state` and `rssi` even with no command activity, so the
   controller (and Home page signal-strength indicator) has fresh data.
4. **Physical safety cutoff**: add a hardware or firmware max-runtime
   guard (e.g. auto motor_off after 30 continuous minutes regardless of
   commands received) so a lost `motor_off` command or a controller
   crash can't leave a pump running indefinitely. Make this duration a
   `#define` near the top of the file, easy to tune per crop/field.

---

## 5. Soil moisture sensing

If the soil moisture sensor is wired to the relay unit (typical, since
it's already out in the field): read it on a timer (e.g. every 5 min),
include the raw reading in the next `heartbeat` status packet's
`payload`-equivalent (extend `LoraStatus` with a `moisture_raw` field,
or send a separate lightweight `sensor_reading` packet type — pick one
and update `shared/lora_protocol.h` accordingly). The controller
forwards it to the backend, which converts raw ADC values to a
`moisture_pct` and writes a `sensor_readings` row (this conversion/
calibration logic belongs in the controller firmware or the backend —
put it in the backend so a calibration change doesn't require
re-flashing every relay unit in the field).

If instead the moisture sensor is wired directly to the controller
unit (single-unit deployments with no separate relay in the field),
skip LoRa for readings entirely and have the controller read + report
directly.

---

## 6. Config / secrets

Never hardcode WiFi credentials or the pairing secret in source that
gets committed. Use:
- `WiFiManager`'s captive portal for WiFi credentials (entered once per
  physical deployment, stored in NVS).
- The pairing secret is generated on-device and only ever leaves the
  device once, during the pairing exchange with the Flutter app — treat
  it like a password, not a build-time constant.

`platformio.ini` should define separate build environments for
`controller` and `relay_unit`, each pinning board type, upload speed,
and the LoRa library version.

---

## 7. Future: SIM card replacement for LoRa

Design lists "LoRa can be replaced by SIM card" as a future feature —
i.e. a controller+relay pair in one unit with a SIM800/SIM7000 module
posting straight to the backend, no local radio hop. Structure
`shared/lora_protocol.h`'s packet types so a future `sim_module`
transport (already a `device_type` option in the `farm_devices` table
per `supabase/002_feature_gap_closure.sql`) can reuse the same
`LoraCommand`/`LoraStatus` shapes serialized as JSON over HTTP instead
of raw structs over radio — don't couple the packet *meaning* to the
LoRa *transport*.
