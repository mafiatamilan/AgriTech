#include <HTTPClient.h>
#include <LoRa.h>
#include <SPI.h>
#include <WebServer.h>
#include <WiFi.h>

#include "local_config.h"

// Wi-Fi ESP32 + SX1278. This board talks to the backend over Wi-Fi and sends
// motor commands to the relay ESP32 over LoRa.

static const char *WIFI_SSID = AGRITECH_WIFI_SSID;
static const char *WIFI_PASSWORD = AGRITECH_WIFI_PASSWORD;

// Backend polling endpoint. A 204 means no command. A 200 response includes
// JSON like {"action":"on"} or {"action":"off"}.
static const char *BACKEND_COMMAND_URL = AGRITECH_BACKEND_BASE_URL "/motor/pending-command?device_uid=" AGRITECH_DEVICE_UID;

// Optional backend status endpoint. Receives JSON status POSTs.
static const char *BACKEND_STATUS_URL = AGRITECH_BACKEND_BASE_URL "/webhooks/hardware-status";
static const char *DEVICE_UID = AGRITECH_DEVICE_UID;
static const char *DEVICE_SECRET = AGRITECH_DEVICE_SECRET;
static const char *HARDWARE_WEBHOOK_SECRET = AGRITECH_HARDWARE_WEBHOOK_SECRET;

static constexpr long LORA_FREQUENCY = 433E6;

static constexpr int LORA_SCK = 18;
static constexpr int LORA_MISO = 19;
static constexpr int LORA_MOSI = 23;
static constexpr int LORA_SS = 5;
static constexpr int LORA_RST = 14;
static constexpr int LORA_DIO0 = 26;

static constexpr unsigned long BACKEND_POLL_MS = 5000;
static constexpr unsigned long ACK_WAIT_MS = 1500;
static constexpr unsigned long HTTP_TIMEOUT_MS = 1500;
static constexpr unsigned long WIFI_CONNECT_TIMEOUT_MS = 20000;
static constexpr unsigned long WIFI_RETRY_MS = 10000;
static constexpr unsigned long BACKEND_ERROR_LOG_MS = 10000;

WebServer server(80);

unsigned long lastBackendPollMs = 0;
unsigned long lastBackendErrorLogMs = 0;
unsigned long lastWiFiRetryMs = 0;
bool wasWiFiConnected = false;
bool pendingLocalStatusReport = false;
String pendingLocalStatus = "";
bool pendingLocalCommand = false;
String pendingLocalCommandState = "";
uint32_t commandSeq = 0;
String lastCommand = "NONE";
String lastAck = "none";
int lastAckRssi = 0;
float lastAckSnr = 0.0;
int lastBackendCode = 0;
String lastBackendBody = "";
String lastBackendAction = "NONE";

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    delay(10);
  }

  Serial.println();
  Serial.println("AgriTech LoRa motor gateway");

  setupLoRa();
  setupWiFi();
  setupHttpServer();
}

void loop() {
  server.handleClient();

  handleSerialCommand();
  maintainWiFi();
  flushLocalCommand();
  flushLocalStatusReport();

  if (strlen(BACKEND_COMMAND_URL) > 0 && millis() - lastBackendPollMs >= BACKEND_POLL_MS) {
    lastBackendPollMs = millis();
    pollBackendCommand();
  }
}

void setupLoRa() {
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

void setupWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("Connecting Wi-Fi");
  unsigned long startedMs = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startedMs < WIFI_CONNECT_TIMEOUT_MS) {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("Wi-Fi connected. IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("Wi-Fi connection failed. Firmware will keep retrying.");
    printNearbyNetworks();
  }
}

void setupHttpServer() {
  server.on("/", HTTP_GET, []() {
    server.send(200, "text/plain", "AgriTech LoRa motor gateway");
  });

  server.on("/motor/on", HTTP_POST, []() {
    queueLocalCommand("ON");
    server.send(202, "application/json", statusJson("queued"));
  });

  server.on("/motor/off", HTTP_POST, []() {
    queueLocalCommand("OFF");
    server.send(202, "application/json", statusJson("queued"));
  });

  server.on("/status", HTTP_GET, []() {
    server.send(200, "application/json", statusJson("ok"));
  });

  server.begin();
  Serial.println("HTTP server started");
  Serial.println("Test with: curl -X POST http://<gateway-ip>/motor/on");
  Serial.println("Type ON or OFF and press Enter.");
}

void handleSerialCommand() {
  if (!Serial.available()) {
    return;
  }

  String command = Serial.readStringUntil('\n');
  command.trim();
  command.toUpperCase();

  if (command == "ON") {
    bool ok = dispatchMotorCommand("ON", false);
    queueLocalStatusReport(ok ? "acked" : "no_ack");
  } else if (command == "OFF") {
    bool ok = dispatchMotorCommand("OFF", false);
    queueLocalStatusReport(ok ? "acked" : "no_ack");
  } else if (command.length() > 0) {
    Serial.print("Unknown command: ");
    Serial.println(command);
    Serial.println("Use ON or OFF.");
  }
}

void queueLocalStatusReport(const String &status) {
  pendingLocalStatus = status;
  pendingLocalStatusReport = true;
}

void queueLocalCommand(const String &motorState) {
  pendingLocalCommandState = motorState;
  pendingLocalCommand = true;
}

void flushLocalCommand() {
  if (!pendingLocalCommand) {
    return;
  }

  String motorState = pendingLocalCommandState;
  pendingLocalCommand = false;
  pendingLocalCommandState = "";

  bool ok = dispatchMotorCommand(motorState, false);
  queueLocalStatusReport(ok ? "acked" : "no_ack");
}

void flushLocalStatusReport() {
  if (!pendingLocalStatusReport) {
    return;
  }

  String status = pendingLocalStatus;
  pendingLocalStatusReport = false;
  pendingLocalStatus = "";
  postStatus(status);
}

void maintainWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    if (!wasWiFiConnected) {
      wasWiFiConnected = true;
      Serial.print("Wi-Fi connected. IP: ");
      Serial.println(WiFi.localIP());
    }
    return;
  }

  wasWiFiConnected = false;

  if (millis() - lastWiFiRetryMs < WIFI_RETRY_MS) {
    return;
  }
  lastWiFiRetryMs = millis();

  Serial.print("Retrying Wi-Fi: ");
  Serial.println(WIFI_SSID);
  WiFi.disconnect();
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

void printNearbyNetworks() {
  Serial.println("Scanning Wi-Fi networks...");
  int count = WiFi.scanNetworks();
  bool sawConfiguredSsid = false;

  for (int i = 0; i < count; i++) {
    String ssid = WiFi.SSID(i);
    Serial.print("SSID: ");
    Serial.print(ssid);
    Serial.print(" | RSSI: ");
    Serial.println(WiFi.RSSI(i));
    if (ssid == WIFI_SSID) {
      sawConfiguredSsid = true;
    }
  }

  if (!sawConfiguredSsid) {
    Serial.print("Configured SSID not found: ");
    Serial.println(WIFI_SSID);
    Serial.println("ESP32 requires a 2.4 GHz Wi-Fi network.");
  }
}

void pollBackendCommand() {
  if (WiFi.status() != WL_CONNECTED) {
    return;
  }

  HTTPClient http;
  http.begin(BACKEND_COMMAND_URL);
  http.setTimeout(HTTP_TIMEOUT_MS);
  http.addHeader("X-Agent-Secret", DEVICE_SECRET);
  http.addHeader("X-Device-Id", DEVICE_UID);

  int code = http.GET();
  String body = http.getString();
  body.trim();
  body.toUpperCase();
  http.end();

  lastBackendCode = code;
  lastBackendBody = body;
  lastBackendAction = "NONE";

  if (code == 204) {
    return;
  }

  if (code < 200 || code >= 300) {
    logBackendError(code, body);
    return;
  }

  String action = actionFromPendingCommand(body);
  lastBackendAction = action;
  if (action == "ON" || action == "OFF") {
    dispatchMotorCommand(action, true);
  }
}

bool dispatchMotorCommand(const String &motorState, bool reportToBackend) {
  String message = "CMD gateway=" + String(DEVICE_UID) +
                   " seq=" + String(commandSeq++) +
                   " motor=" + motorState;

  LoRa.beginPacket();
  LoRa.print(message);
  LoRa.endPacket();

  lastCommand = motorState;
  Serial.print("LoRa sent: ");
  Serial.println(message);

  bool acked = waitForAck(motorState);
  if (reportToBackend) {
    postStatus(acked ? "acked" : "no_ack");
  }
  return acked;
}

bool waitForAck(const String &motorState) {
  unsigned long startedMs = millis();

  while (millis() - startedMs < ACK_WAIT_MS) {
    int packetSize = LoRa.parsePacket();
    if (packetSize == 0) {
      delay(10);
      continue;
    }

    String message;
    while (LoRa.available()) {
      message += static_cast<char>(LoRa.read());
    }

    lastAck = message;
    lastAckRssi = LoRa.packetRssi();
    lastAckSnr = LoRa.packetSnr();

    Serial.print("LoRa received: ");
    Serial.print(message);
    Serial.print(" | RSSI: ");
    Serial.print(lastAckRssi);
    Serial.print(" dBm | SNR: ");
    Serial.print(lastAckSnr);
    Serial.println(" dB");

    if (message.startsWith("ACK") && message.indexOf("motor=" + motorState) >= 0) {
      return true;
    }
  }

  Serial.println("No ACK from relay node");
  return false;
}

void postStatus(const String &status) {
  if (strlen(BACKEND_STATUS_URL) == 0 || WiFi.status() != WL_CONNECTED) {
    return;
  }

  HTTPClient http;
  http.begin(BACKEND_STATUS_URL);
  http.setTimeout(HTTP_TIMEOUT_MS);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-Agent-Secret", HARDWARE_WEBHOOK_SECRET);
  http.addHeader("X-Device-Id", DEVICE_UID);

  int code = http.POST(hardwareStatusJson(status));
  Serial.print("Status POST: ");
  Serial.println(code);
  http.end();
}

void logBackendError(int code, const String &body) {
  if (millis() - lastBackendErrorLogMs < BACKEND_ERROR_LOG_MS) {
    return;
  }
  lastBackendErrorLogMs = millis();

  Serial.print("Backend poll failed: ");
  Serial.println(code);
  if (body.length() > 0) {
    Serial.print("Backend response: ");
    Serial.println(body);
  }
}

String statusJson(const String &status) {
  return String("{\"device_uid\":\"") + DEVICE_UID +
         "\",\"status\":\"" + status +
         "\",\"last_command\":\"" + lastCommand +
         "\",\"last_ack\":\"" + lastAck +
         "\",\"last_ack_rssi\":" + String(lastAckRssi) +
         ",\"last_ack_snr\":" + String(lastAckSnr, 2) +
         ",\"last_backend_code\":" + String(lastBackendCode) +
         ",\"last_backend_action\":\"" + lastBackendAction + "\"" +
         ",\"last_backend_body\":\"" + jsonEscape(lastBackendBody) + "\"" +
         ",\"ip\":\"" + WiFi.localIP().toString() +
         "\"}";
}

String hardwareStatusJson(const String &status) {
  String eventType = "heartbeat";
  if (lastCommand == "ON" && status == "acked") {
    eventType = "motor_on";
  } else if (lastCommand == "OFF" && status == "acked") {
    eventType = "motor_off";
  } else if (status == "no_ack") {
    eventType = "error";
  }

  return String("{\"device_uid\":\"") + DEVICE_UID +
         "\",\"event_type\":\"" + eventType +
         "\",\"signal_strength\":" + String(lastAckRssi) +
         ",\"payload\":{" +
         "\"status\":\"" + status + "\"," +
         "\"motor_state\":\"" + lastCommand + "\"," +
         "\"last_ack\":\"" + jsonEscape(lastAck) + "\"," +
         "\"last_ack_snr\":" + String(lastAckSnr, 2) + "," +
         "\"firmware_version\":\"lora-gateway-0.1.0\"," +
         "\"ip\":\"" + WiFi.localIP().toString() + "\"" +
         "}}";
}

String actionFromPendingCommand(const String &body) {
  String normalized = body;
  normalized.toLowerCase();
  normalized.replace(" ", "");
  normalized.replace("\n", "");
  normalized.replace("\r", "");

  if (normalized.indexOf("\"action\":\"on\"") >= 0) {
    return "ON";
  }
  if (normalized.indexOf("\"action\":\"off\"") >= 0) {
    return "OFF";
  }
  if (normalized == "on") {
    return "ON";
  }
  if (normalized == "off") {
    return "OFF";
  }
  return "NONE";
}

String jsonEscape(const String &value) {
  String escaped;
  for (size_t i = 0; i < value.length(); i++) {
    char c = value.charAt(i);
    if (c == '\\' || c == '"') {
      escaped += '\\';
    }
    escaped += c;
  }
  return escaped;
}
