// ══════════════════════════════════════════════════════════════════════
// AgriTech — Arduino UNO Relay Unit
// Receives: LoRa B ←──wireless──← LoRa A ← ESP32 ← MQTT ← Backend
// Controls: Relay → Motor/Pump
//
// • Receives MOTOR_ON / MOTOR_OFF commands over LoRa
// • Validates commands and prevents duplicate execution
// • Sends ACK with matching command_id
// • Implements 30-minute safety timeout
// • Sends periodic heartbeat status
// ══════════════════════════════════════════════════════════════════════

#include <Arduino.h>
#include <LoRa.h>
#include <SPI.h>

// ── Shared protocol ─────────────────────────────────────────────────
#include "lora_protocol.h"

// ── Pin definitions (from platformio.ini build flags) ───────────────
#ifndef LORA_SCK
#define LORA_SCK    13
#endif
#ifndef LORA_MISO
#define LORA_MISO   12
#endif
#ifndef LORA_MOSI
#define LORA_MOSI   11
#endif
#ifndef LORA_CS
#define LORA_CS     10
#endif
#ifndef LORA_RST
#define LORA_RST    9
#endif
#ifndef LORA_DIO0
#define LORA_DIO0   2
#endif

#ifndef RELAY_PIN
#define RELAY_PIN   7
#endif

#ifndef RELAY_ACTIVE_HIGH
#define RELAY_ACTIVE_HIGH 1
#endif

// ── State ───────────────────────────────────────────────────────────
uint8_t  motorState         = MOTOR_OFF;
uint32_t lastExecutedCmdId  = 0;     // dedup: last command we acted on
uint8_t  lastExecutedAction = 0;     // pkt_type of last executed command
unsigned long motorOnSince  = 0;     // millis() when motor was turned ON
unsigned long lastHeartbeat = 0;

// ── Forward declarations ────────────────────────────────────────────
void loraInit();
void relayInit();
void relayOn();
void relayOff();
void sendAck(uint32_t commandId, int8_t rssi);
void sendStatus(int8_t rssi);
void sendError(uint8_t errorCode, int8_t rssi);
void handleCommand(LoraCommand &cmd, int8_t rssi);
void safetyCheck();

// ══════════════════════════════════════════════════════════════════════
// setup()
// ══════════════════════════════════════════════════════════════════════
void setup() {
    Serial.begin(9600);
    delay(1000);
    Serial.println("\n=== AgriTech Arduino UNO Relay Unit ===");

    relayInit();
    loraInit();

    // Ensure motor is OFF at boot
    relayOff();

    Serial.println("Setup complete — listening on LoRa.\n");
}

// ══════════════════════════════════════════════════════════════════════
// loop()
// ══════════════════════════════════════════════════════════════════════
void loop() {
    // ── Check for incoming LoRa packets from ESP32 ──────────────────
    int packetSize = LoRa.parsePacket();
    if (packetSize == sizeof(LoraCommand)) {
        LoraCommand cmd;
        uint8_t buf[sizeof(LoraCommand)];
        int idx = 0;
        while (LoRa.available() && idx < (int)sizeof(LoraCommand)) {
            buf[idx++] = LoRa.read();
        }
        memcpy(&cmd, buf, sizeof(LoraCommand));

        int8_t rssi = LoRa.packetRssi();
        Serial.printf("[LoRa RX] pkt=0x%02X cmd_id=%lu  rssi=%d\n",
                      cmd.pkt_type, cmd.command_id, rssi);

        handleCommand(cmd, rssi);
    }

    // ── Periodic heartbeat ──────────────────────────────────────────
    if (millis() - lastHeartbeat >= HEARTBEAT_INTERVAL_MS) {
        lastHeartbeat = millis();
        sendStatus(LoRa.packetRssi());
        Serial.printf("[Heartbeat] motor=%s  cmd_id=%lu\n",
                      motorState == MOTOR_ON ? "ON" : "OFF", lastExecutedCmdId);
    }

    // ── Safety timeout ──────────────────────────────────────────────
    safetyCheck();
}

// ══════════════════════════════════════════════════════════════════════
// Command handling
// ══════════════════════════════════════════════════════════════════════
void handleCommand(LoraCommand &cmd, int8_t rssi) {
    // ── Duplicate detection ─────────────────────────────────────────
    if (cmd.command_id == lastExecutedCmdId && cmd.pkt_type == lastExecutedAction) {
        Serial.printf("[Dedup] cmd_id=%lu already executed — resending ACK\n",
                      cmd.command_id);
        sendAck(cmd.command_id, rssi);
        return;
    }

    // ── Validate command type ───────────────────────────────────────
    if (cmd.pkt_type != PKT_MOTOR_ON &&
        cmd.pkt_type != PKT_MOTOR_OFF &&
        cmd.pkt_type != PKT_PING &&
        cmd.pkt_type != PKT_STATUS_REQUEST) {
        Serial.printf("[Error] Unknown pkt_type 0x%02X\n", cmd.pkt_type);
        sendError(ERR_INVALID_CMD, rssi);
        return;
    }

    // ── Execute command ─────────────────────────────────────────────
    switch (cmd.pkt_type) {
        case PKT_MOTOR_ON:
            if (motorState == MOTOR_OFF) {
                relayOn();
                motorState = MOTOR_ON;
                motorOnSince = millis();
                Serial.println("[Relay] Motor turned ON");
            } else {
                Serial.println("[Relay] Motor already ON — no change");
            }
            sendAck(cmd.command_id, rssi);
            break;

        case PKT_MOTOR_OFF:
            if (motorState == MOTOR_ON) {
                relayOff();
                motorState = MOTOR_OFF;
                motorOnSince = 0;
                Serial.println("[Relay] Motor turned OFF");
            } else {
                Serial.println("[Relay] Motor already OFF — no change");
            }
            sendAck(cmd.command_id, rssi);
            break;

        case PKT_PING:
            sendAck(cmd.command_id, rssi);
            break;

        case PKT_STATUS_REQUEST:
            sendStatus(rssi);
            break;
    }

    lastExecutedCmdId  = cmd.command_id;
    lastExecutedAction = cmd.pkt_type;
}

// ══════════════════════════════════════════════════════════════════════
// Relay control
// ══════════════════════════════════════════════════════════════════════
void relayInit() {
    pinMode(RELAY_PIN, OUTPUT);
    relayOff();
}

void relayOn() {
#if RELAY_ACTIVE_HIGH
    digitalWrite(RELAY_PIN, HIGH);
#else
    digitalWrite(RELAY_PIN, LOW);
#endif
}

void relayOff() {
#if RELAY_ACTIVE_HIGH
    digitalWrite(RELAY_PIN, LOW);
#else
    digitalWrite(RELAY_PIN, HIGH);
#endif
}

// ══════════════════════════════════════════════════════════════════════
// Safety timeout
// ══════════════════════════════════════════════════════════════════════
void safetyCheck() {
    if (motorState == MOTOR_ON && motorOnSince > 0) {
        unsigned long runtime = millis() - motorOnSince;
        if (runtime >= (unsigned long)SAFETY_TIMEOUT_MS) {
            Serial.printf("[SAFETY] Motor ran for %lu ms — forcing OFF\n", runtime);
            relayOff();
            motorState = MOTOR_OFF;
            motorOnSince = 0;
            lastExecutedCmdId = 0;
            lastExecutedAction = 0;
            sendError(ERR_SAFETY_TIMEOUT, LoRa.packetRssi());
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// LoRa TX helpers
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

void sendAck(uint32_t commandId, int8_t rssi) {
    LoraStatus ack;
    ack.pkt_type   = PKT_ACK;
    ack.command_id = commandId;
    ack.motor_state = motorState;
    ack.rssi       = rssi;
    ack.error_code = ERR_NONE;

    LoRa.beginPacket();
    LoRa.write((uint8_t*)&ack, sizeof(LoraStatus));
    LoRa.endPacket();

    Serial.printf("[LoRa TX] ACK  cmd_id=%lu  motor=%d\n", commandId, motorState);
}

void sendStatus(int8_t rssi) {
    LoraStatus st;
    st.pkt_type   = PKT_STATUS;
    st.command_id = lastExecutedCmdId;
    st.motor_state = motorState;
    st.rssi       = rssi;
    st.error_code = ERR_NONE;

    LoRa.beginPacket();
    LoRa.write((uint8_t*)&st, sizeof(LoraStatus));
    LoRa.endPacket();

    Serial.printf("[LoRa TX] STATUS  motor=%d  cmd_id=%lu\n", motorState, lastExecutedCmdId);
}

void sendError(uint8_t errorCode, int8_t rssi) {
    LoraStatus err;
    err.pkt_type   = PKT_ERROR;
    err.command_id = lastExecutedCmdId;
    err.motor_state = motorState;
    err.rssi       = rssi;
    err.error_code = errorCode;

    LoRa.beginPacket();
    LoRa.write((uint8_t*)&err, sizeof(LoraStatus));
    LoRa.endPacket();

    Serial.printf("[LoRa TX] ERROR  code=%d\n", errorCode);
}
