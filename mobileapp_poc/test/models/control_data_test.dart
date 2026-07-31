import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp_poc/models/control_data.dart';

void main() {
  test('ControlData.fromJson parses a valid control blob', () {
    final data = ControlData.fromJson('{"setpoint": 25.0, "relay": true}');
    expect(data.setpoint, 25.0);
    expect(data.relay, true);
  });

  test('ControlData.toJson produces a parseable round trip', () {
    const data = ControlData(setpoint: 18.5, relay: false);
    final roundTripped = ControlData.fromJson(data.toJson());
    expect(roundTripped.setpoint, 18.5);
    expect(roundTripped.relay, false);
  });

  test('ControlData.fromJson throws FormatException on malformed input', () {
    expect(() => ControlData.fromJson('not json'), throwsFormatException);
  });

  test('ControlData.fromJson throws FormatException on missing required field', () {
    expect(() => ControlData.fromJson('{"setpoint": 25.0}'), throwsFormatException);
  });

  test('ControlData.fromJson throws FormatException on wrong-typed value', () {
    expect(() => ControlData.fromJson('{"setpoint": "25.0", "relay": true}'), throwsFormatException);
  });
}
