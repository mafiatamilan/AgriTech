#include <LoRa.h>
#include <SPI.h>

// Non-Wi-Fi ESP32 + SX1278. This board receives LoRa motor commands and drives
// the relay connected to the pump or motor contactor.

static const char *NODE_ID = "relay-001";
static constexpr long LORA_FREQUENCY = 433E6;

static constexpr int LORA_SCK = 18;
static constexpr int LORA_MISO = 19;
static constexpr int LORA_MOSI = 23;
static constexpr int LORA_SS = 5;
static constexpr int LORA_RST = 14;
static constexpr int LORA_DIO0 = 26;

static constexpr int RELAY_PIN = 25;
static constexpr bool RELAY_ACTIVE_LOW = true;
static constexpr unsigned long HEARTBEAT_MS = 10000;

String motorState = "OFF";
unsigned long lastHeartbeatMs = 0;

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    delay(10);
  }

  Serial.println();
  Serial.println("AgriTech LoRa motor relay node");
  Serial.println("Relay signal pin: GPIO 25");

  pinMode(RELAY_PIN, OUTPUT);
  setMotor(false);
  delay(1000);

  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_SS);
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

  if (!LoRa.begin(LORA_FREQUENCY)) {
    Serial.println("LoRa init failed. Check wiring, power, and frequency.");
    while (true) {
      delay(1000);
    }
  }

  LoRa.setSyncWord(0x34);
  LoRa.setTxPower(17);
  LoRa.enableCrc();

  Serial.println("LoRa init ok");
}

void loop() {
  handleSerialCommand();
  printHeartbeat();

  int packetSize = LoRa.parsePacket();
  if (packetSize == 0) {
    return;
  }

  String message;
  while (LoRa.available()) {
    message += static_cast<char>(LoRa.read());
  }

  int rssi = LoRa.packetRssi();
  float snr = LoRa.packetSnr();

  Serial.print("LoRa received: ");
  Serial.print(message);
  Serial.print(" | RSSI: ");
  Serial.print(rssi);
  Serial.print(" dBm | SNR: ");
  Serial.print(snr);
  Serial.println(" dB");

  if (!message.startsWith("CMD")) {
    return;
  }

  if (message.indexOf("motor=ON") >= 0) {
    setMotor(true);
    sendAck(rssi, snr);
  } else if (message.indexOf("motor=OFF") >= 0) {
    setMotor(false);
    sendAck(rssi, snr);
  }
}

void handleSerialCommand() {
  if (!Serial.available()) {
    return;
  }

  String command = Serial.readStringUntil('\n');
  command.trim();
  command.toUpperCase();

  if (command == "ON") {
    setMotor(true);
  } else if (command == "OFF") {
    setMotor(false);
  } else if (command.length() > 0) {
    Serial.print("Unknown USB command: ");
    Serial.println(command);
    Serial.println("Use ON or OFF.");
  }
}

void printHeartbeat() {
  if (millis() - lastHeartbeatMs < HEARTBEAT_MS) {
    return;
  }
  lastHeartbeatMs = millis();

  Serial.print("Relay node alive. Motor: ");
  Serial.println(motorState);
}

void setMotor(bool on) {
  String nextState = on ? "ON" : "OFF";
  bool changed = nextState != motorState;
  motorState = nextState;
  digitalWrite(RELAY_PIN, relayLevel(on));

  Serial.print(changed ? "Motor state changed: " : "Motor state unchanged: ");
  Serial.println(motorState);
}

int relayLevel(bool on) {
  if (RELAY_ACTIVE_LOW) {
    return on ? LOW : HIGH;
  }

  return on ? HIGH : LOW;
}

void sendAck(int receivedRssi, float receivedSnr) {
  String reply = "ACK node=" + String(NODE_ID) +
                 " motor=" + motorState +
                 " rssi=" + String(receivedRssi) +
                 " snr=" + String(receivedSnr, 2);

  LoRa.beginPacket();
  LoRa.print(reply);
  LoRa.endPacket();

  Serial.print("LoRa sent: ");
  Serial.println(reply);
}
