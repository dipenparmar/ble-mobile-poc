#include <ArduinoBLE.h>
#include <ArduinoJson.h>

const char* SERVICE_UUID    = "12345678-1234-5678-1234-56789abc0000";
const char* TELEMETRY_UUID  = "12345678-1234-5678-1234-56789abc0001";
const char* CONTROL_UUID    = "12345678-1234-5678-1234-56789abc0002";
const char* DEVICE_NAME     = "XIAO-POC";

BLEService bleService(SERVICE_UUID);
BLECharacteristic telemetryChar(TELEMETRY_UUID, BLERead | BLENotify, 64);
BLECharacteristic controlChar(CONTROL_UUID, BLERead | BLEWrite, 64);

float setpoint = 25.0;
bool relayOn = false;
unsigned long lastTelemetryMs = 0;
const unsigned long TELEMETRY_INTERVAL_MS = 1000;

void updateControlCharacteristic() {
  StaticJsonDocument<64> doc;
  doc["setpoint"] = setpoint;
  doc["relay"] = relayOn;
  char buf[64];
  size_t len = serializeJson(doc, buf, sizeof(buf));
  controlChar.writeValue((const uint8_t*)buf, len);
}

void onControlWritten(BLEDevice central, BLECharacteristic characteristic) {
  int len = characteristic.valueLength();
  char buf[65];
  int copyLen = len < 64 ? len : 64;
  memcpy(buf, characteristic.value(), copyLen);
  buf[copyLen] = '\0';

  StaticJsonDocument<64> doc;
  DeserializationError err = deserializeJson(doc, buf);
  if (err) {
    Serial.print("Control JSON parse error: ");
    Serial.println(err.c_str());
    // Reset the characteristic back to the last-known-good state so a
    // subsequent read doesn't see the malformed bytes that were just written.
    updateControlCharacteristic();
    return;
  }

  setpoint = doc["setpoint"] | setpoint;
  relayOn = doc["relay"] | relayOn;
  digitalWrite(LED_BUILTIN, relayOn ? LOW : HIGH); // LED_BUILTIN is active-low on XIAO nRF52840

  // Keep the characteristic's stored value in sync with setpoint/relayOn so a
  // future read always reflects the current, valid state.
  updateControlCharacteristic();

  Serial.print("Received setpoint=");
  Serial.print(setpoint);
  Serial.print(" relay=");
  Serial.println(relayOn);
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH); // off (active-low)

  if (!BLE.begin()) {
    Serial.println("BLE init failed!");
    while (1) { delay(1000); }
  }

  BLE.setLocalName(DEVICE_NAME);
  BLE.setAdvertisedService(bleService);
  bleService.addCharacteristic(telemetryChar);
  bleService.addCharacteristic(controlChar);
  BLE.addService(bleService);

  controlChar.setEventHandler(BLEWritten, onControlWritten);
  updateControlCharacteristic();

  BLE.advertise();
  Serial.println("XIAO-POC advertising");
}

void loop() {
  BLE.poll();

  unsigned long now = millis();
  if (now - lastTelemetryMs >= TELEMETRY_INTERVAL_MS) {
    lastTelemetryMs = now;

    float temp = 20.0 + (float)(now % 10000) / 1000.0; // simulated 20-30 range
    float hum = 50.0 + (float)(now % 5000) / 250.0;     // simulated 50-70 range
    int batt = 100 - (int)((now / 60000) % 100);         // simulated slow drain

    StaticJsonDocument<64> doc;
    doc["temp"] = temp;
    doc["hum"] = hum;
    doc["batt"] = batt;
    char buf[64];
    size_t len = serializeJson(doc, buf, sizeof(buf));
    telemetryChar.writeValue((const uint8_t*)buf, len);
  }
}
