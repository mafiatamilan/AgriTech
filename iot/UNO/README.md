# AgriTech — Irrigation Control Hardware (ESP32 + Arduino UNO + LoRa)

```
Soil Moisture Sensing Agent
        ↓
    Backend (MQTT)
        ↓
   ESP32 (MQTT subscriber)
        ↓
     LoRa A  (SX1278)
        ↓ wireless
     LoRa B  (SX1278)
        ↓
   Arduino UNO
        ↓
     Relay Module
        ↓
   Motor / Pump
```

---

## 1. Repository Structure

```
iot/UNO/
├── platformio.ini               # PlatformIO build configuration
├── shared/
│   └── lora_protocol.h          # Shared binary packet definitions
├── controller/
│   └── src/main.cpp             # ESP32 firmware (Wi-Fi + MQTT + LoRa A)
├── relay_unit/
│   └── src/main.cpp             # Arduino UNO firmware (LoRa B + relay)
└── README.md                    # This file
```

---

## 2. Pin Tables

### 2.1 ESP32 DevKit V1 ↔ LoRa A (SX1278 / RA-02)

| ESP32 Pin | LoRa A Pin | Function           |
|-----------|------------|--------------------|
| GPIO18    | SCK        | SPI clock          |
| GPIO19    | MISO       | SPI data in        |
| GPIO23    | MOSI       | SPI data out       |
| GPIO5     | NSS / CS   | SPI chip select    |
| GPIO14    | RST        | Module reset       |
| GPIO26    | DIO0       | IRQ (packet ready) |
| 3.3V      | VCC        | Power supply       |
| GND       | GND        | Ground             |

### 2.2 Arduino UNO ↔ LoRa B (SX1278 / RA-02)

| Arduino Pin | LoRa B Pin | Function           |
|-------------|------------|--------------------|
| D13         | SCK        | SPI clock          |
| D12         | MISO       | SPI data in        |
| D11         | MOSI       | SPI data out       |
| D10         | NSS / CS   | SPI chip select    |
| D9          | RST        | Module reset       |
| D2          | DIO0       | IRQ (packet ready) |
| 3.3V*       | VCC        | Power supply       |
| GND         | GND        | Ground             |

### 2.3 Arduino UNO ↔ Relay Module

| Arduino Pin | Relay Pin | Function          |
|-------------|-----------|-------------------|
| D7          | IN        | Control signal    |
| 5V          | VCC       | Relay power       |
| GND         | GND       | Ground            |

### 2.4 Relay Module ↔ Motor / Pump

| Relay Pin | Motor/Pump | Function           |
|-----------|------------|--------------------|
| COM       | Live/Phase | Mains or battery + |
| NO        | Motor +    | Switched output    |
| (NC)      | —          | Not connected      |

---

## 3. Wiring Diagrams

### 3.1 ESP32 ↔ LoRa A

```
   ESP32 DevKit V1              SX1278 / RA-02 (LoRa A)
  ┌─────────────────┐          ┌─────────────────┐
  │             3V3 ├──────────┤ VCC             │
  │             GND ├──────────┤ GND             │
  │                 │          │                 │
  │          GPIO18 ├──────────┤ SCK             │
  │          GPIO19 ├──────────┤ MISO            │
  │          GPIO23 ├──────────┤ MOSI            │
  │           GPIO5 ├──────────┤ NSS / CS        │
  │          GPIO14 ├──────────┤ RST             │
  │          GPIO26 ├──────────┤ DIO0            │
  └─────────────────┘          └─────────────────┘
```

### 3.2 Arduino UNO ↔ LoRa B

```
   Arduino UNO                 SX1278 / RA-02 (LoRa B)
  ┌─────────────────┐          ┌─────────────────┐
  │             3V3 ├──────────┤ VCC  (see §4)   │
  │             GND ├──────────┤ GND             │
  │                 │          │                 │
  │           D13   ├──────────┤ SCK             │
  │           D12   ├──────────┤ MISO            │
  │           D11   ├──────────┤ MOSI            │
  │           D10   ├──────────┤ NSS / CS        │
  │           D9    ├──────────┤ RST             │
  │           D2    ├──────────┤ DIO0            │
  └─────────────────┘          └─────────────────┘
```

### 3.3 Arduino UNO ↔ Relay Module

```
   Arduino UNO                 Relay Module (active-HIGH)
  ┌─────────────────┐          ┌─────────────────┐
  │             D7  ├──────────┤ IN              │
  │             5V  ├──────────┤ VCC             │
  │             GND ├──────────┤ GND             │
  └─────────────────┘          └────────┬────────┘
                                        │
                                   ┌────┴────┐
                                   │  Motor   │
                                   │  /Pump   │
                                   └─────────┘
```

### 3.4 Complete System Wiring

```
 ┌──────────────┐        ┌──────────────┐
 │  ESP32       │        │  LoRa A      │
 │  DevKit V1   │◄──────►│  SX1278      │
 │              │  SPI   │              │
 └──────┬───────┘        └──────┬───────┘
        │                       │
        │ WiFi                  │ LoRa 433 MHz
        │                       │ (wireless)
        ▼                       │
 ┌──────────────┐               │
 │  MQTT Broker │               │
 └──────────────┘               │
                                │
                       ┌────────┴───────┐
                       │  LoRa B        │
                       │  SX1278        │
                       │                │
                       └────────┬───────┘
                                │
                                │ SPI
                       ┌────────┴───────┐
                       │  Arduino UNO   │
                       │                │
                       └────────┬───────┘
                                │
                                │ D7
                       ┌────────┴───────┐
                       │  Relay Module  │
                       │                │
                       └────────┬───────┘
                                │
                                │ COM → NO
                       ┌────────┴───────┐
                       │  Motor / Pump  │
                       └────────────────┘
```

---

## 4. 3.3V Level Shifting — SX1278 on Arduino UNO (5V)

The SX1278 operates at **3.3V logic**. The Arduino UNO operates at **5V logic**.
Connecting 5V data lines directly to the SX1278 **will damage it**.

### Why it works with SPI (on most boards)

The SX1278's SPI pins (SCK, MOSI, MISO, NSS) are **5V-tolerant** on most
SX1278 / RA-02 modules. This is because:

- SCK, MOSI, NSS are **inputs** to the SX1278 — the module tolerates 5V HIGH
  on these pins.
- MISO is an **output** from the SX1278 (3.3V) — the Arduino UNO reads 3.3V
  as HIGH since its threshold is ~3.0V.

**However**, RST and DIO0 are **not** 5V-tolerant on all modules.

### Safe approach — Level shifter or resistor divider

For RST (output from UNO → input to SX1278):

```
Arduino D9 ────[1kΩ]────┬──── SX1278 RST
                         │
                       [2kΩ]
                         │
                        GND
```

This forms a voltage divider: `Vout = 5V × 2k/(1k+2k) ≈ 3.3V`.

For DIO0 (output from SX1278 → input to UNO):

```
SX1278 DIO0 ──────────── Arduino D2
```

3.3V output from SX1278 is sufficient to read as HIGH on the Arduino UNO
(threshold ~3.0V). No level shifting needed for this direction.

### Alternative: Use a bidirectional logic level shifter

A common module like the **BSS138-based bidirectional level shifter** handles
all lines cleanly:

```
Arduino 5V  ── HV side    LV side ── 3.3V (SX1278 VCC)
Arduino D9  ── HV1        LV1     ── SX1278 RST
GND          ── GND        GND     ── GND
```

### Recommendation

For a production deployment, use a **level shifter module**. For prototyping,
the resistor divider on RST is sufficient since DIO0 reads fine at 3.3V on
the UNO. If your specific SX1278 module's datasheet confirms 5V tolerance
on RST, you can connect directly.

---

## 5. LoRa Binary Protocol

### Packet sizes (must match exactly)

| Packet      | Size    | Fields                                   |
|-------------|---------|------------------------------------------|
| LoraCommand | 5 bytes | `pkt_type` (1) + `command_id` (4)        |
| LoraStatus  | 8 bytes | `pkt_type` (1) + `command_id` (4) + `motor_state` (1) + `rssi` (1) + `error_code` (1) |

### Packet types

| Value  | Name             | Direction      | Description               |
|--------|------------------|----------------|---------------------------|
| 0x01   | PKT_MOTOR_ON     | ESP32 → Arduino | Turn motor ON            |
| 0x02   | PKT_MOTOR_OFF    | ESP32 → Arduino | Turn motor OFF           |
| 0x03   | PKT_PING         | ESP32 → Arduino | Heartbeat ping           |
| 0x04   | PKT_STATUS_REQUEST | ESP32 → Arduino | Request current status |
| 0x10   | PKT_ACK          | Arduino → ESP32 | Acknowledge command      |
| 0x11   | PKT_STATUS       | Arduino → ESP32 | Current motor status     |
| 0x12   | PKT_ERROR        | Arduino → ESP32 | Error report             |

### Error codes

| Code | Name               | Meaning                          |
|------|--------------------|----------------------------------|
| 0x00 | ERR_NONE           | No error                         |
| 0x01 | ERR_RELAY_STUCK    | Relay did not respond            |
| 0x02 | ERR_SAFETY_TIMEOUT | 30-min safety cutoff triggered   |
| 0x03 | ERR_INVALID_CMD    | Unknown packet type received     |
| 0x04 | ERR_COMM_LOST      | Communication lost               |

---

## 6. MQTT Topics

| Topic                              | Direction    | Payload                          |
|------------------------------------|--------------|----------------------------------|
| `farm/{farm_id}/irrigation/command` | Backend → ESP32 | `{"command_id": 101, "action": "MOTOR_ON"}` |
| `farm/{farm_id}/irrigation/status`  | ESP32 → Backend | `{"motor_state": "ON", "signal_strength": -72, "relay_online": true}` |
| `farm/{farm_id}/irrigation/error`   | ESP32 → Backend | `{"error": "Command failed — no ACK from relay"}` |

Override topics at build time via PlatformIO build flags:

```ini
build_flags = -D TOPIC_CMD=\"farm/myfarm/irrigation/command\"
              -D TOPIC_STATUS=\"farm/myfarm/irrigation/status\"
              -D TOPIC_ERROR=\"farm/myfarm/irrigation/error\"
```

---

## 7. MQTT Command Format

```json
{
  "command_id": 101,
  "action": "MOTOR_ON"
}
```

Valid actions: `MOTOR_ON`, `MOTOR_OFF`, `PING`, `STATUS_REQUEST`

---

## 8. Safety Features

| Feature                        | Location   | Behavior                                              |
|--------------------------------|------------|-------------------------------------------------------|
| Command deduplication          | Arduino    | Same `command_id` + same action → resend ACK only     |
| Maximum motor runtime          | Arduino    | Auto OFF after 30 min (`SAFETY_TIMEOUT_MS`)           |
| Retry with ACK                 | ESP32      | Up to 3 retries if no ACK received                    |
| Motor boots OFF                | Arduino    | `relayOff()` called in `setup()`                      |
| MQTT reconnect                 | ESP32      | Auto-reconnect in loop                                |
| WiFi reconnect                 | ESP32      | Auto-reconnect in loop                                |

---

## 9. Build & Flash

### Prerequisites

- [PlatformIO CLI](https://platformio.org/install/cli) or PlatformIO IDE
- USB cables for ESP32 and Arduino UNO

### Build both environments

```bash
cd iot/UNO
pio run -e controller      # ESP32
pio run -e relay_unit       # Arduino UNO
```

### Flash

```bash
pio run -e controller -t upload      # Flash ESP32 (disconnect UNO first)
pio run -e relay_unit -t upload      # Flash Arduino UNO (disconnect ESP32 first)
```

### Monitor serial output

```bash
pio device monitor -e controller     # 115200 baud
pio device monitor -e relay_unit     # 9600 baud
```

---

## 10. End-to-End Test Procedure

### Step 1: Hardware setup

1. Wire ESP32 ↔ LoRa A per §3.1
2. Wire Arduino UNO ↔ LoRa B per §3.2
3. Wire Arduino UNO ↔ Relay per §3.3
4. Connect relay COM/NO to motor power supply
5. **Do NOT connect motor to mains for initial test — use a LED or buzzer on the relay output**

### Step 2: Flash firmware

```bash
pio run -e controller -t upload
pio run -e relay_unit -t upload
```

### Step 3: Open serial monitors

```bash
# Terminal 1 — ESP32
pio device monitor -e controller

# Terminal 2 — Arduino UNO
pio device monitor -e relay_unit
```

Expected output on ESP32:
```
=== AgriTech ESP32 Controller ===
[WiFi] Connected — IP: 192.168.1.xxx
[LoRa] Ready on 433.0 MHz  SF9  BW125 kHz
[MQTT] Connecting to broker.emqx.io:1883 ... connected.
[MQTT] Subscribed to farm/default/irrigation/command
```

Expected output on Arduino:
```
=== AgriTech Arduino UNO Relay Unit ===
[LoRa] Ready on 433.0 MHz  SF9  BW125 kHz
Setup complete — listening on LoRa.
```

### Step 4: Test MOTOR_ON via MQTT

Use any MQTT client (e.g., [MQTTX](https://mqttx.app/), `mosquitto_pub`):

```bash
mosquitto_pub -h broker.emqx.io -t "farm/default/irrigation/command" \
  -m '{"command_id": 101, "action": "MOTOR_ON"}'
```

Expected on ESP32 serial:
```
[MQTT RX] topic=farm/default/irrigation/command  payload={"command_id":101,"action":"MOTOR_ON"}
[LoRa TX] attempt 1/3  pkt=0x01 cmd_id=101
[LoRa] ACK received for cmd_id=101
[MQTT TX] status: {"motor_state":"ON","signal_strength":-72,"relay_online":true}
```

Expected on Arduino serial:
```
[LoRa RX] pkt=0x01 cmd_id=101  rssi=-68
[Relay] Motor turned ON
[LoRa TX] ACK  cmd_id=101  motor=1
```

**Relay should click ON. Motor should start running.**

### Step 5: Test MOTOR_OFF via MQTT

```bash
mosquitto_pub -h broker.emqx.io -t "farm/default/irrigation/command" \
  -m '{"command_id": 102, "action": "MOTOR_OFF"}'
```

Expected:
- ESP32 sends `MOTOR_OFF` to Arduino via LoRa
- Arduino turns relay OFF, sends ACK
- ESP32 publishes `{"motor_state":"OFF",...}`

**Relay should click OFF. Motor should stop.**

### Step 6: Test duplicate command rejection

Send the same command twice:

```bash
mosquitto_pub -h broker.emqx.io -t "farm/default/irrigation/command" \
  -m '{"command_id": 103, "action": "MOTOR_ON"}'
# Wait for ACK...
mosquitto_pub -h broker.emqx.io -t "farm/default/irrigation/command" \
  -m '{"command_id": 103, "action": "MOTOR_ON"}'
```

Expected on Arduino:
```
[LoRa RX] pkt=0x01 cmd_id=103  rssi=-70
[Relay] Motor turned ON
[LoRa TX] ACK  cmd_id=103  motor=1

[LoRa RX] pkt=0x01 cmd_id=103  rssi=-71
[Dedup] cmd_id=103 already executed — resending ACK
[LoRa TX] ACK  cmd_id=103  motor=1
```

**Motor should NOT toggle — it stays ON, duplicate ACK is resent.**

### Step 7: Test safety timeout

1. Send `MOTOR_ON` with `command_id: 200`
2. Wait 30 minutes (or temporarily reduce `SAFETY_TIMEOUT_MS` in `platformio.ini` to e.g. `30000` for 30 seconds)
3. Arduino should auto-turn OFF the motor and send an error

Expected on Arduino:
```
[SAFETY] Motor ran for 1800000 ms — forcing OFF
[LoRa TX] ERROR  code=2
```

### Step 8: Test PING

```bash
mosquitto_pub -h broker.emqx.io -t "farm/default/irrigation/command" \
  -m '{"command_id": 301, "action": "PING"}'
```

Arduino should respond with an ACK — motor state unchanged.

### Step 9: Test STATUS_REQUEST

```bash
mosquitto_pub -h broker.emqx.io -t "farm/default/irrigation/command" \
  -m '{"command_id": 401, "action": "STATUS_REQUEST"}'
```

Arduino should respond with a STATUS packet containing current motor state.

---

## 11. Configuration Reference

All configurable values can be set via PlatformIO build flags in `platformio.ini`:

| Build flag                | Default          | Description                          |
|---------------------------|------------------|--------------------------------------|
| `WIFI_SSID`               | `"your-ssid"`    | Wi-Fi network name                   |
| `WIFI_PASS`               | `"your-password"`| Wi-Fi password                       |
| `MQTT_BROKER`             | `"broker.emqx.io"` | MQTT broker hostname              |
| `MQTT_PORT`               | `1883`           | MQTT broker port                     |
| `MQTT_USER`               | `""`             | MQTT username (optional)             |
| `MQTT_PASS`               | `""`             | MQTT password (optional)             |
| `TOPIC_CMD`               | `"farm/default/irrigation/command"` | Command topic |
| `TOPIC_STATUS`            | `"farm/default/irrigation/status"` | Status topic  |
| `TOPIC_ERROR`             | `"farm/default/irrigation/error"`  | Error topic   |
| `LORA_FREQUENCY`          | `433.0`          | LoRa frequency in MHz               |
| `LORA_SPREAD_FACTOR`      | `9`              | LoRa spreading factor (6–12)        |
| `LORA_BANDWIDTH`          | `125.0`          | LoRa bandwidth in kHz               |
| `LORA_TX_POWER`           | `17`             | LoRa TX power in dBm                |
| `LORA_SYNC_WORD`          | `0x12`           | LoRa sync word (private network)    |
| `LORA_RETRY_COUNT`        | `3`              | Max retries per command             |
| `LORA_RETRY_DELAY_MS`     | `1000`           | Delay between retries in ms         |
| `HEARTBEAT_INTERVAL_MS`   | `60000`          | Heartbeat interval in ms            |
| `SAFETY_TIMEOUT_MS`       | `1800000`        | Max motor runtime before auto-OFF   |
| `RELAY_ACTIVE_HIGH`       | `1`              | 1 = active-HIGH relay, 0 = active-LOW |
| `RELAY_PIN`               | `7` (UNO)        | Arduino pin connected to relay IN   |
