# ESP32 LoRa Pair Test

This folder contains a minimal Arduino CLI test for two ESP32 boards with
SX127x LoRa modules.

Use this before integrating with the AgriTech firmware:

- `lora_ping_sender`: broadcasts `DISCOVER` packets and listens for replies.
- `lora_ping_receiver`: listens for `DISCOVER` packets and replies with `ACK`.

## Default Wiring

Both ESP32 boards should use the same wiring:

| LoRa pin | ESP32 pin |
|---|---:|
| VCC | 3.3V |
| GND | GND |
| SCK | GPIO 18 |
| MISO | GPIO 19 |
| MOSI | GPIO 23 |
| NSS / CS | GPIO 5 |
| RST | GPIO 14 |
| DIO0 / IRQ | GPIO 26 |

Do not power the LoRa module from 5V. Use 3.3V only.

## Frequency

Both sketches default to `433E6` for SX1278 modules. Change
`LORA_FREQUENCY` in both sketches only if your modules are a different band.
Both boards must use the same frequency.

## Install Requirements

```bash
arduino-cli core update-index
arduino-cli core install esp32:esp32
arduino-cli lib install LoRa
```

## Find Both USB Ports

```bash
arduino-cli board list
```

If serial discovery is blocked by permissions, try:

```bash
ls /dev/ttyUSB* /dev/ttyACM*
```

## Compile

```bash
arduino-cli compile --fqbn esp32:esp32:esp32 lora_ping_sender
arduino-cli compile --fqbn esp32:esp32:esp32 lora_ping_receiver
```

## Upload

Replace the ports with the two ports from `arduino-cli board list`.

```bash
arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32 lora_ping_sender
arduino-cli upload -p /dev/ttyUSB1 --fqbn esp32:esp32:esp32 lora_ping_receiver
```

## Monitor

Open two terminals:

```bash
arduino-cli monitor -p /dev/ttyUSB0 -c baudrate=115200
arduino-cli monitor -p /dev/ttyUSB1 -c baudrate=115200
```

Expected result:

- Sender prints `Sent: DISCOVER...`
- Receiver prints `Received: DISCOVER...` and `Sent: ACK...`
- Sender prints `Received: ACK...` with RSSI and SNR values

## Motor Relay Flow

After the ping test works, use these sketches:

- `lora_motor_gateway_wifi`: ESP32 connected to Wi-Fi and LoRa A.
- `lora_motor_relay_node`: ESP32 not connected to Wi-Fi, connected to LoRa B
  and the relay module.

Flow:

```text
Backend -> Wi-Fi ESP32 -> LoRa A -> LoRa B -> Relay ESP32 -> Relay -> Motor
```

The gateway supports local test endpoints:

```bash
curl -X POST http://<gateway-ip>/motor/on
curl -X POST http://<gateway-ip>/motor/off
curl http://<gateway-ip>/status
```

Edit these values in `lora_motor_gateway_wifi/local_config.h` before
uploading:

```cpp
#define AGRITECH_WIFI_SSID "CHANGE_ME"
#define AGRITECH_WIFI_PASSWORD "CHANGE_ME"
#define AGRITECH_BACKEND_BASE_URL "http://192.168.1.20:8000"
#define AGRITECH_DEVICE_UID "gateway-001"
#define AGRITECH_DEVICE_SECRET "CHANGE_ME"
#define AGRITECH_HARDWARE_WEBHOOK_SECRET "CHANGE_ME"
```

Pair the device in the backend with the same `AGRITECH_DEVICE_UID` and
`AGRITECH_DEVICE_SECRET`. The backend queues commands through:

```text
GET /motor/pending-command?device_uid=gateway-001
```

The gateway reports LoRa ACKs and motor state to:

```text
POST /webhooks/hardware-status
```

If your relay module turns on when it should be off, change this in
`lora_motor_relay_node/lora_motor_relay_node.ino`:

```cpp
static constexpr bool RELAY_ACTIVE_LOW = true;
```

Compile:

```bash
arduino-cli compile --fqbn esp32:esp32:esp32 --build-path /tmp/lora_motor_gateway_build lora_motor_gateway_wifi
arduino-cli compile --fqbn esp32:esp32:esp32 --build-path /tmp/lora_motor_relay_build lora_motor_relay_node
```

Upload:

```bash
arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32 --input-dir /tmp/lora_motor_gateway_build lora_motor_gateway_wifi
arduino-cli upload -p /dev/ttyUSB1 --fqbn esp32:esp32:esp32 --input-dir /tmp/lora_motor_relay_build lora_motor_relay_node
```

Relay wiring depends on your relay module, but the default signal pin is:

| Relay pin | ESP32 pin |
|---|---:|
| IN | GPIO 27 |
| VCC | Relay module rated input |
| GND | GND |

Use a proper relay module or contactor for the motor load. Do not drive a
pump or mains motor directly from an ESP32 pin.
