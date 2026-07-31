import 'package:flutter/material.dart';
import 'services/ble_service.dart';
import 'screens/scan_screen.dart';

void main() {
  runApp(const BleDashboardApp());
}

class BleDashboardApp extends StatelessWidget {
  const BleDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Dashboard POC',
      home: ScanScreen(bleService: BleService()),
    );
  }
}
