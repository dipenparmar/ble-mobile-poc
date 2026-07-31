import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../ble_constants.dart';
import '../models/telemetry_data.dart';
import '../models/control_data.dart';

class BleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _telemetryChar;
  BluetoothCharacteristic? _controlChar;

  final _telemetryController = StreamController<TelemetryData>.broadcast();
  Stream<TelemetryData> get telemetryStream => _telemetryController.stream;

  Stream<BluetoothConnectionState> get connectionStateStream =>
      _device == null
          ? const Stream<BluetoothConnectionState>.empty()
          : _device!.connectionState;

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Stream<List<ScanResult>> scan() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    return FlutterBluePlus.scanResults;
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect();
    final services = await device.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid.toString().toLowerCase() == BleConstants.serviceUuid,
    );
    _telemetryChar = service.characteristics.firstWhere(
      (c) => c.uuid.toString().toLowerCase() == BleConstants.telemetryCharUuid,
    );
    _controlChar = service.characteristics.firstWhere(
      (c) => c.uuid.toString().toLowerCase() == BleConstants.controlCharUuid,
    );

    await _telemetryChar!.setNotifyValue(true);
    _telemetryChar!.lastValueStream.listen((bytes) {
      if (bytes.isEmpty) return;
      try {
        final data = TelemetryData.fromJson(String.fromCharCodes(bytes));
        _telemetryController.add(data);
      } on FormatException {
        // Malformed notify payload — skip this update, keep last-known values.
      }
    });
  }

  Future<ControlData> readControl() async {
    final bytes = await _controlChar!.read();
    return ControlData.fromJson(String.fromCharCodes(bytes));
  }

  Future<void> writeControl(ControlData data) async {
    await _controlChar!.write(data.toJson().codeUnits, withoutResponse: false);
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _telemetryChar = null;
    _controlChar = null;
  }

  void dispose() {
    _telemetryController.close();
  }
}
