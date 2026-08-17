#ifndef LORA_PROTOCOL_H
#define LORA_PROTOCOL_H

#include <stdint.h>

// ── Packet types ────────────────────────────────────────────────────
// Controller -> Relay (commands)
#define PKT_MOTOR_ON       0x01
#define PKT_MOTOR_OFF      0x02
#define PKT_PING           0x03
#define PKT_STATUS_REQUEST 0x04

// Relay -> Controller (responses)
#define PKT_ACK            0x10
#define PKT_STATUS         0x11
#define PKT_ERROR          0x12

// ── Packet structs (fixed-size, byte-aligned) ───────────────────────
// Controller -> Relay
#pragma pack(push, 1)
struct LoraCommand {
    uint8_t  pkt_type;     // PKT_MOTOR_ON / PKT_MOTOR_OFF / PKT_PING / PKT_STATUS_REQUEST
    uint32_t command_id;   // monotonically increasing, for dedup + ACK matching
};

// Relay -> Controller
struct LoraStatus {
    uint8_t  pkt_type;     // PKT_ACK / PKT_STATUS / PKT_ERROR
    uint32_t command_id;   // echoes the command being ACKed, or 0 for heartbeat
    uint8_t  motor_state;  // 0 = OFF, 1 = ON
    int8_t   rssi;         // signal strength as seen by receiver
    uint8_t  error_code;   // 0 = no error, non-zero for PKT_ERROR
};
#pragma pack(pop)

// ── Error codes ─────────────────────────────────────────────────────
#define ERR_NONE           0x00
#define ERR_RELAY_STUCK    0x01
#define ERR_SAFETY_TIMEOUT 0x02
#define ERR_INVALID_CMD    0x03
#define ERR_COMM_LOST      0x04

// ── Motor state helpers ─────────────────────────────────────────────
#define MOTOR_OFF 0
#define MOTOR_ON  1

// ── Defaults ────────────────────────────────────────────────────────
#define LORA_FREQUENCY      433.0f   // MHz — change to 868.0 or 915.0 for your region
#define LORA_BANDWIDTH      125.0f   // kHz
#define LORA_SPREAD_FACTOR  9
#define LORA_TX_POWER       17       // dBm (max for SX1278)
#define LORA_SYNC_WORD      0x12     // private network, change for yours
#define LORA_CRC_ON         true

// Retry / timing defaults (overridable in platformio.ini build flags)
#ifndef LORA_RETRY_COUNT
#define LORA_RETRY_COUNT    3
#endif

#ifndef LORA_RETRY_DELAY_MS
#define LORA_RETRY_DELAY_MS 1000
#endif

#ifndef HEARTBEAT_INTERVAL_MS
#define HEARTBEAT_INTERVAL_MS 60000  // 60 s
#endif

#ifndef SAFETY_TIMEOUT_MS
#define SAFETY_TIMEOUT_MS   1800000  // 30 minutes
#endif

#endif // LORA_PROTOCOL_H
