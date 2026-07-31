import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp_poc/models/telemetry_data.dart';

void main() {
  test('TelemetryData.fromJson parses a valid telemetry blob', () {
    final data = TelemetryData.fromJson('{"temp": 23.5, "hum": 61.2, "batt": 87}');
    expect(data.temp, 23.5);
    expect(data.hum, 61.2);
    expect(data.batt, 87);
  });

  test('TelemetryData.toJson produces a parseable round trip', () {
    const data = TelemetryData(temp: 20.0, hum: 50.0, batt: 100);
    final roundTripped = TelemetryData.fromJson(data.toJson());
    expect(roundTripped.temp, 20.0);
    expect(roundTripped.hum, 50.0);
    expect(roundTripped.batt, 100);
  });

  test('TelemetryData.fromJson throws FormatException on malformed input', () {
    expect(() => TelemetryData.fromJson('not json'), throwsFormatException);
  });
}
