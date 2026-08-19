#include <SPI.h>
#include <LoRa.h>

static constexpr long LORA_FREQUENCY = 433E6;

static constexpr int LORA_SCK = 18;
static constexpr int LORA_MISO = 19;
static constexpr int LORA_MOSI = 23;
static constexpr int LORA_SS = 5;
static constexpr int LORA_RST = 14;
static constexpr int LORA_DIO0 = 26;

unsigned long lastSendMs = 0;
uint32_t packetCounter = 0;

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    delay(10);
  }

  Serial.println();
  Serial.println("ESP32 LoRa discovery sender");

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
  if (millis() - lastSendMs >= 3000) {
    lastSendMs = millis();
    sendDiscover();
  }

  receiveReply();
}

void sendDiscover() {
  String message = "DISCOVER sender=esp32-a seq=" + String(packetCounter++);

  LoRa.beginPacket();
  LoRa.print(message);
  LoRa.endPacket();

  Serial.print("Sent: ");
  Serial.println(message);
}

void receiveReply() {
  int packetSize = LoRa.parsePacket();
  if (packetSize == 0) {
    return;
  }

  String message;
  while (LoRa.available()) {
    message += static_cast<char>(LoRa.read());
  }

  Serial.print("Received: ");
  Serial.print(message);
  Serial.print(" | RSSI: ");
  Serial.print(LoRa.packetRssi());
  Serial.print(" dBm | SNR: ");
  Serial.print(LoRa.packetSnr());
  Serial.println(" dB");
}
