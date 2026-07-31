import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../ble_constants.dart';
import 'dashboard_screen.dart';

class ScanScreen extends StatefulWidget {
  final BleService bleService;

  const ScanScreen({required this.bleService, super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> _results = [];
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    final granted = await widget.bleService.requestPermissions();
    if (!granted) {
      setState(() => _error = 'Bluetooth/location permission denied.');
      return;
    }
    widget.bleService.scan().listen((results) {
      setState(() {
        _results = results.where((r) => r.device.platformName.isNotEmpty).toList();
      });
    });
  }

  Future<void> _connect(ScanResult result) async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await widget.bleService.stopScan();
      await widget.bleService.connect(result.device);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(bleService: widget.bleService),
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'Failed to connect: $e';
        _connecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan for ${BleConstants.deviceName}')),
      body: _connecting
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      return ListTile(
                        title: Text(result.device.platformName),
                        subtitle: Text('RSSI: ${result.rssi}'),
                        onTap: () => _connect(result),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
