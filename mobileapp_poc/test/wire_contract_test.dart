// Pins the wire contract shared between the Arduino firmware
// (firmware/xiao_ble_poc/xiao_ble_poc.ino) and this Flutter app. If either
// side's JSON shape, buffer size, or UUIDs drift, this test should fail
// instead of only surfacing as a hardware-only bug.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp_poc/ble_constants.dart';
import 'package:mobileapp_poc/models/control_data.dart';
import 'package:mobileapp_poc/models/telemetry_data.dart';

void main() {
  test(
    'TelemetryData.fromJson parses whole-number values as ArduinoJson emits them',
    () {
      // ArduinoJson's serializeJson() emits whole-valued floats without a
      // decimal point (e.g. "20" rather than "20.0") — this is the literal
      // shape the firmware sends on boot before the simulated values drift.
      final data = TelemetryData.fromJson('{"temp": 20, "hum": 50, "batt": 100}');
      expect(data.temp, 20.0);
      expect(data.hum, 50.0);
      expect(data.batt, 100);
    },
  );

  test(
    'ControlData.fromJson parses whole-number setpoint as ArduinoJson emits it',
    () {
      final data = ControlData.fromJson('{"setpoint": 25, "relay": false}');
      expect(data.setpoint, 25.0);
      expect(data.relay, false);
    },
  );

  test(
    'ControlData.toJson fits within the firmware\'s 64-byte control buffer',
    () {
      // firmware/xiao_ble_poc/xiao_ble_poc.ino declares:
      //   BLECharacteristic controlChar(CONTROL_UUID, BLERead | BLEWrite, 64);
      const data = ControlData(setpoint: 25.0, relay: false);
      final utf8Length = utf8.encode(data.toJson()).length;
      expect(utf8Length, lessThanOrEqualTo(64));
    },
  );

  test('BleConstants UUIDs match the literals hardcoded in the firmware', () {
    // Read from firmware/xiao_ble_poc/xiao_ble_poc.ino:
    //   SERVICE_UUID    = "12345678-1234-5678-1234-56789abc0000"
    //   TELEMETRY_UUID  = "12345678-1234-5678-1234-56789abc0001"
    //   CONTROL_UUID    = "12345678-1234-5678-1234-56789abc0002"
    expect(BleConstants.serviceUuid, '12345678-1234-5678-1234-56789abc0000');
    expect(BleConstants.telemetryCharUuid, '12345678-1234-5678-1234-56789abc0001');
    expect(BleConstants.controlCharUuid, '12345678-1234-5678-1234-56789abc0002');
  });
}
