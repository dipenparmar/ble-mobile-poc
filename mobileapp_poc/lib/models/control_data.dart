import 'dart:convert';

class ControlData {
  final double setpoint;
  final bool relay;

  const ControlData({required this.setpoint, required this.relay});

  factory ControlData.fromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return ControlData(
        setpoint: (map['setpoint'] as num).toDouble(),
        relay: map['relay'] as bool,
      );
    } catch (e) {
      throw FormatException('Invalid control JSON: $e');
    }
  }

  String toJson() => jsonEncode({'setpoint': setpoint, 'relay': relay});
}
