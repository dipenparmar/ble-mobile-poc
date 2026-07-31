import 'dart:convert';

class TelemetryData {
  final double temp;
  final double hum;
  final int batt;

  const TelemetryData({required this.temp, required this.hum, required this.batt});

  factory TelemetryData.fromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return TelemetryData(
        temp: (map['temp'] as num).toDouble(),
        hum: (map['hum'] as num).toDouble(),
        batt: (map['batt'] as num).toInt(),
      );
    } catch (e) {
      throw FormatException('Invalid telemetry JSON: $e');
    }
  }

  String toJson() => jsonEncode({'temp': temp, 'hum': hum, 'batt': batt});
}
