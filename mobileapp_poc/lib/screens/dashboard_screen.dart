import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../models/telemetry_data.dart';
import '../models/control_data.dart';
import 'scan_screen.dart';

class DashboardScreen extends StatefulWidget {
  final BleService bleService;

  const DashboardScreen({required this.bleService, super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  TelemetryData? _telemetry;
  final _setpointController = TextEditingController();
  bool _relay = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitialControl();
    widget.bleService.telemetryStream.listen((data) {
      setState(() => _telemetry = data);
    });
    widget.bleService.connectionStateStream.listen((state) {
      if (state == BluetoothConnectionState.disconnected && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ScanScreen(bleService: widget.bleService),
          ),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device disconnected')),
        );
      }
    });
  }

  Future<void> _loadInitialControl() async {
    try {
      final control = await widget.bleService.readControl();
      setState(() {
        _setpointController.text = control.setpoint.toString();
        _relay = control.relay;
      });
    } catch (e) {
      setState(() => _error = 'Failed to read initial control state: $e');
    }
  }

  Future<void> _sendControl() async {
    final setpoint = double.tryParse(_setpointController.text);
    if (setpoint == null) {
      setState(() => _error = 'Setpoint must be a number');
      return;
    }
    try {
      await widget.bleService.writeControl(
        ControlData(setpoint: setpoint, relay: _relay),
      );
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = 'Write failed: $e');
    }
  }

  @override
  void dispose() {
    _setpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final telemetry = _telemetry;
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            Text('Temperature: ${telemetry?.temp.toStringAsFixed(1) ?? '--'} C'),
            Text('Humidity: ${telemetry?.hum.toStringAsFixed(1) ?? '--'} %'),
            Text('Battery: ${telemetry?.batt ?? '--'} %'),
            const SizedBox(height: 24),
            TextField(
              controller: _setpointController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Setpoint'),
            ),
            Row(
              children: [
                const Text('Relay:'),
                Switch(
                  value: _relay,
                  onChanged: (value) => setState(() => _relay = value),
                ),
              ],
            ),
            ElevatedButton(onPressed: _sendControl, child: const Text('Send')),
          ],
        ),
      ),
    );
  }
}
