// ══════════════════════════════════════════════════════════════════════
// AgriTech — ESP32 Irrigation Controller
// Connects: WiFi → MQTT → LoRa A ──wireless──→ LoRa B → Arduino UNO
// No physical sensors — all irrigation decisions come from the
// Soil Moisture Sensing Agent via MQTT.
// ══════════════════════════════════════════════════════════════════════

#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <LoRa.h>
#include <SPI.h>
#include <Preferences.h>

// ── Shared protocol ─────────────────────────────────────────────────
#include "lora_protocol.h"

// ── Pin definitions (from platformio.ini build flags) ───────────────
#ifndef LORA_SCK
#define LORA_SCK    18
#endif
#ifndef LORA_MISO
#define LORA_MISO   19
#endif
#ifndef LORA_MOSI
#define LORA_MOSI   23
#endif
#ifndef LORA_CS
#define LORA_CS     5
#endif
#ifndef LORA_RST
#define LORA_RST    14
#endif
#ifndef LORA_DIO0
#define LORA_DIO0   26
#endif

// ── Wi-Fi ───────────────────────────────────────────────────────────
#ifndef WIFI_SSID
#define WIFI_SSID "your-ssid"
#endif
#ifndef WIFI_PASS
#define WIFI_PASS "your-password"
#endif

// ── MQTT ────────────────────────────────────────────────────────────
#ifndef MQTT_BROKER
#define MQTT_BROKER "broker.emqx.io"
#endif
#ifndef MQTT_PORT
#define MQTT_PORT 1883
#endif

// ── MQTT topics (configurable via build flags) ──────────────────────
#ifndef TOPIC_CMD
#define TOPIC_CMD   "farm/default/irrigation/command"
#endif
#ifndef TOPIC_STATUS
#define TOPIC_STATUS "farm/default/irrigation/status"
#endif
#ifndef TOPIC_ERROR
#define TOPIC_ERROR  "farm/default/irrigation/error"
#endif

// ── Objects ─────────────────────────────────────────────────────────
WiFiClient   wifiClient;
PubSubClient mqtt(wifiClient);
Preferences  prefs;

// ── State ───────────────────────────────────────────────────────────
uint32_t    nextCommandId   = 0;
LoraStatus  lastRelayStatus;
bool        gotStatus       = false;
unsigned long lastLoRaSend  = 0;
int         loraSendCount   = 0;

// ── Forward declarations ────────────────────────────────────────────
void wifiConnect();
void mqttCallback(char* topic, byte* payload, unsigned int length);
bool mqttReconnect();
void loraInit();
bool loraSendCommand(uint8_t pktType, uint32_t commandId);
bool loraWaitAck(uint32_t commandId, unsigned long timeoutMs);
void publishMotorStatus(uint8_t motorState, int8_t rssi);
void publishError(const char* msg);

// ══════════════════════════════════════════════════════════════════════
// setup()
// ══════════════════════════════════════════════════════════════════════
void setup() {
    Serial.begin(115200);
    delay(1000);
    Serial.println("\n=== AgriTech ESP32 Controller ===");

    // Retrieve last-used command_id across reboots
    prefs.begin("agritech", false);
    nextCommandId = prefs.getUInt("cmd_id", 0);
    prefs.end();
    Serial.printf("Resuming command_id: %lu\n", nextCommandId);

    wifiConnect();
    loraInit();

    mqtt.setServer(MQTT_BROKER, MQTT_PORT);
    mqtt.setCallback(mqttCallback);
    mqtt.setBufferSize(512);

    Serial.println("Setup complete — entering loop.\n");
}

// ══════════════════════════════════════════════════════════════════════
// loop()
// ══════════════════════════════════════════════════════════════════════
void loop() {
    // ── Wi-Fi keepalive ─────────────────────────────────────────────
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[WiFi] Disconnected — reconnecting...");
        wifiConnect();
    }

    // ── MQTT keepalive ──────────────────────────────────────────────
    if (!mqtt.connected()) {
        mqttReconnect();
    }
    mqtt.loop();

    // ── Check for incoming LoRa packets from Arduino ────────────────
    int packetSize = LoRa.parsePacket();
    if (packetSize == sizeof(LoraStatus)) {
        LoraStatus status;
        uint8_t buf[sizeof(LoraStatus)];
        int idx = 0;
        while (LoRa.available() && idx < (int)sizeof(LoraStatus)) {
            buf[idx++] = LoRa.read();
        }
        memcpy(&status, buf, sizeof(LoraStatus));
        lastRelayStatus = status;
        gotStatus = true;

        int8_t rssi = LoRa.packetRssi();
        Serial.printf("[LoRa RX] pkt=0x%02X cmd_id=%lu motor=%d rssi=%d err=%d\n",
                      status.pkt_type, status.command_id, status.motor_state,
                      rssi, status.error_code);

        if (status.pkt_type == PKT_ACK) {
            // ACK already handled in loraWaitAck, but publish status too
            publishMotorStatus(status.motor_state, rssi);
        } else if (status.pkt_type == PKT_STATUS) {
            publishMotorStatus(status.motor_state, rssi);
        } else if (status.pkt_type == PKT_ERROR) {
            publishError("Relay unit reported error");
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// Wi-Fi
// ══════════════════════════════════════════════════════════════════════
void wifiConnect() {
    Serial.printf("[WiFi] Connecting to %s", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);

    int retries = 0;
    while (WiFi.status() != WL_CONNECTED && retries < 40) {
        delay(500);
        Serial.print(".");
        retries++;
    }

    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("\n[WiFi] Connected — IP: %s\n", WiFi.localIP().toString().c_str());
    } else {
        Serial.println("\n[WiFi] Failed — will retry in loop.");
    }
}

// ══════════════════════════════════════════════════════════════════════
// MQTT
// ══════════════════════════════════════════════════════════════════════
void mqttCallback(char* topic, byte* payload, unsigned int length) {
    char msg[256];
    unsigned int copyLen = min(length, (unsigned int)(sizeof(msg) - 1));
    memcpy(msg, payload, copyLen);
    msg[copyLen] = '\0';

    Serial.printf("[MQTT RX] topic=%s  payload=%s\n", topic, msg);

    // Parse JSON command
    StaticJsonDocument<128> doc;
    if (deserializeJson(doc, msg)) {
        Serial.println("[MQTT] JSON parse failed");
        publishError("Invalid JSON command");
        return;
    }

    uint32_t commandId = doc["command_id"] | 0;
    const char* action  = doc["action"] | "";

    if (commandId == 0) {
        publishError("Missing command_id");
        return;
    }

    // Map action to LoRa packet type
    uint8_t pktType = 0;
    if (strcmp(action, "MOTOR_ON") == 0) {
        pktType = PKT_MOTOR_ON;
    } else if (strcmp(action, "MOTOR_OFF") == 0) {
        pktType = PKT_MOTOR_OFF;
    } else if (strcmp(action, "PING") == 0) {
        pktType = PKT_PING;
    } else if (strcmp(action, "STATUS_REQUEST") == 0) {
        pktType = PKT_STATUS_REQUEST;
    } else {
        Serial.printf("[MQTT] Unknown action: %s\n", action);
        publishError("Unknown action");
        return;
    }

    // Send command to relay via LoRa with retries
    bool acked = false;
    for (int attempt = 1; attempt <= LORA_RETRY_COUNT; attempt++) {
        Serial.printf("[LoRa TX] attempt %d/%d  pkt=0x%02X cmd_id=%lu\n",
                      attempt, LORA_RETRY_COUNT, pktType, commandId);

        loraSendCommand(pktType, commandId);

        // Wait for ACK (with timeout)
        if (loraWaitAck(commandId, LORA_RETRY_DELAY_MS)) {
            acked = true;
            Serial.printf("[LoRa] ACK received for cmd_id=%lu\n", commandId);
            break;
        }

        Serial.printf("[LoRa] No ACK — retrying in %d ms\n", LORA_RETRY_DELAY_MS);
        delay(LORA_RETRY_DELAY_MS);
    }

    if (!acked) {
        Serial.printf("[LoRa] Command %lu failed after %d attempts\n",
                      commandId, LORA_RETRY_COUNT);
        publishError("Command failed — no ACK from relay");
    }

    // Persist command_id
    prefs.begin("agritech", false);
    prefs.putUInt("cmd_id", commandId);
    prefs.end();
}

bool mqttReconnect() {
    if (WiFi.status() != WL_CONNECTED) return false;

    Serial.printf("[MQTT] Connecting to %s:%d ...", MQTT_BROKER, MQTT_PORT);
    String clientId = "agritech-esp32-" + String((uint32_t)ESP.getEfuseMac(), HEX);

    if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS)) {
        Serial.println(" connected.");
        mqtt.subscribe(TOPIC_CMD);
        Serial.printf("[MQTT] Subscribed to %s\n", TOPIC_CMD);
        return true;
    }

    Serial.printf(" failed (rc=%d) — retrying in 5s\n", mqtt.state());
    delay(5000);
    return false;
}

void publishMotorStatus(uint8_t motorState, int8_t rssi) {
    StaticJsonDocument<128> doc;
    doc["motor_state"] = (motorState == MOTOR_ON) ? "ON" : "OFF";
    doc["signal_strength"] = rssi;
    doc["relay_online"] = true;

    char buf[128];
    serializeJson(doc, buf, sizeof(buf));
    mqtt.publish(TOPIC_STATUS, buf);
    Serial.printf("[MQTT TX] status: %s\n", buf);
}

void publishError(const char* msg) {
    StaticJsonDocument<128> doc;
    doc["error"] = msg;

    char buf[128];
    serializeJson(doc, buf, sizeof(buf));
    mqtt.publish(TOPIC_ERROR, buf);
    Serial.printf("[MQTT TX] error: %s\n", buf);
}

// ══════════════════════════════════════════════════════════════════════
// LoRa
// ══════════════════════════════════════════════════════════════════════
void loraInit() {
    SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_CS);
    LoRa.setPins(LORA_CS, LORA_RST, LORA_DIO0);

    if (!LoRa.begin(LORA_FREQUENCY * 1E6)) {
        Serial.println("[LoRa] Init FAILED — halting.");
        while (true) delay(1000);
    }

    LoRa.setSpreadingFactor(LORA_SPREAD_FACTOR);
    LoRa.setSignalBandwidth(LORA_BANDWIDTH * 1E3);
    LoRa.setTxPower(LORA_TX_POWER);
    LoRa.setSyncWord(LORA_SYNC_WORD);
    LoRa.enableCrc();

    Serial.printf("[LoRa] Ready on %.1f MHz  SF%d  BW%.0f kHz\n",
                  LORA_FREQUENCY, LORA_SPREAD_FACTOR, LORA_BANDWIDTH);
}

bool loraSendCommand(uint8_t pktType, uint32_t commandId) {
    LoraCommand cmd;
    cmd.pkt_type   = pktType;
    cmd.command_id = commandId;

    LoRa.beginPacket();
    LoRa.write((uint8_t*)&cmd, sizeof(LoraCommand));
    LoRa.endPacket();

    lastLoRaSend = millis();
    loraSendCount++;
    return true;
}

bool loraWaitAck(uint32_t commandId, unsigned long timeoutMs) {
    unsigned long start = millis();

    while (millis() - start < timeoutMs) {
        int packetSize = LoRa.parsePacket();
        if (packetSize == sizeof(LoraStatus)) {
            LoraStatus status;
            uint8_t buf[sizeof(LoraStatus)];
            int idx = 0;
            while (LoRa.available() && idx < (int)sizeof(LoraStatus)) {
                buf[idx++] = LoRa.read();
            }
            memcpy(&status, buf, sizeof(LoraStatus));

            if (status.pkt_type == PKT_ACK && status.command_id == commandId) {
                lastRelayStatus = status;
                return true;
            }
        }
        delay(10);
    }
    return false;
}
