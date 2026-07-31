# BLE Dashboard POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter app + Arduino firmware pair that exchange 5 parameters over BLE (3 telemetry values notified from device to app, 2 control values written from app to device) and display them on a local dashboard screen.

**Architecture:** Two independent components joined only by a custom GATT profile. Firmware (Arduino sketch on a Seeed XIAO nRF52840 Sense, ArduinoBLE on the mbed-enabled board core) advertises a service with a Telemetry characteristic (read+notify, JSON) and a Control characteristic (read+write, JSON). The Flutter app (Android+iOS) scans, connects, subscribes to Telemetry, and writes Control on user action, using `flutter_blue_plus` and plain `StatefulWidget` state management (no Provider/Riverpod/Bloc — single-screen POC).

**Tech Stack:** Flutter (Dart), `flutter_blue_plus`, `permission_handler`; Arduino (C++) on Seeed XIAO nRF52840 Sense using the mbed-enabled Seeed nRF52 board package and the `ArduinoBLE` library.

## Global Constraints

- Service UUID: `12345678-1234-5678-1234-56789abc0000`
- Telemetry characteristic UUID: `12345678-1234-5678-1234-56789abc0001` — properties: Read, Notify
- Control characteristic UUID: `12345678-1234-5678-1234-56789abc0002` — properties: Read, Write
- Both characteristics carry a JSON string as UTF-8 bytes (not packed binary)
- Telemetry JSON schema: `{"temp": <double>, "hum": <double>, "batt": <int>}`
- Control JSON schema: `{"setpoint": <double>, "relay": <bool>}`
- Device advertises as `"XIAO-POC"`
- Telemetry notifies ~once per second
- Control writes always send the full JSON blob (both fields together), never a partial update
- No cloud sync, no local persistence, no auto-reconnect, no multi-device management (per spec's Out of Scope)

---

## File Structure

```
mobileapp-poc/
├── firmware/
│   └── xiao_ble_poc/
│       └── xiao_ble_poc.ino          # Arduino sketch, full firmware
├── mobileapp_poc/                     # Flutter project root
│   ├── pubspec.yaml
│   ├── android/app/src/main/AndroidManifest.xml   # BLE permissions
│   ├── ios/Runner/Info.plist                       # BLE usage strings
│   ├── lib/
│   │   ├── main.dart                  # App entry, MaterialApp, ScanScreen as home
│   │   ├── ble_constants.dart         # Service/characteristic UUIDs (shared)
│   │   ├── models/
│   │   │   ├── telemetry_data.dart    # TelemetryData: fromJson/toJson
│   │   │   └── control_data.dart      # ControlData: fromJson/toJson
│   │   ├── services/
│   │   │   └── ble_service.dart       # BleService: scan/connect/telemetryStream/writeControl
│   │   └── screens/
│   │       ├── scan_screen.dart       # Device discovery list
│   │       └── dashboard_screen.dart  # Telemetry display + controls
│   └── test/
│       └── models/
│           ├── telemetry_data_test.dart
│           └── control_data_test.dart
```

---

### Task 1: Flutter project scaffold, dependencies, and platform permissions

**Files:**
- Create: `mobileapp_poc/` (via `flutter create`)
- Modify: `mobileapp_poc/pubspec.yaml`
- Modify: `mobileapp_poc/android/app/src/main/AndroidManifest.xml`
- Modify: `mobileapp_poc/android/app/build.gradle` (minSdkVersion)
- Modify: `mobileapp_poc/ios/Runner/Info.plist`

**Interfaces:**
- Produces: a runnable empty Flutter app with `flutter_blue_plus` and `permission_handler` available for import in later tasks.

- [ ] **Step 1: Create the Flutter project**

Run: `flutter create --org com.example mobileapp_poc`

- [ ] **Step 2: Add dependencies to pubspec.yaml**

In `mobileapp_poc/pubspec.yaml`, under `dependencies:`, add:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_blue_plus: ^1.32.0
  permission_handler: ^11.3.0
```

- [ ] **Step 3: Run pub get**

Run: `cd mobileapp_poc && flutter pub get`
Expected: completes with no errors, `pubspec.lock` created/updated.

- [ ] **Step 4: Set Android minSdkVersion and add BLE permissions**

In `mobileapp_poc/android/app/build.gradle`, inside the `defaultConfig` block, ensure:

```gradle
minSdkVersion 21
```

In `mobileapp_poc/android/app/src/main/AndroidManifest.xml`, add these lines as direct children of `<manifest>`, before `<application>`:

```xml
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
```

- [ ] **Step 5: Add iOS Bluetooth usage strings**

In `mobileapp_poc/ios/Runner/Info.plist`, add these keys as direct children of the root `<dict>`:

```xml
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>This app uses Bluetooth to connect to your BLE sensor device.</string>
	<key>NSBluetoothPeripheralUsageDescription</key>
	<string>This app uses Bluetooth to connect to your BLE sensor device.</string>
```

- [ ] **Step 6: Verify the app builds**

Run: `cd mobileapp_poc && flutter analyze`
Expected: "No issues found!" (default counter-app template still in `lib/main.dart` at this point — that's fine, it gets replaced in Task 6).

- [ ] **Step 7: Commit**

```bash
git add mobileapp_poc
git commit -m "Scaffold Flutter project with BLE dependencies and permissions"
```

---

### Task 2: BLE constants and TelemetryData model (TDD)

**Files:**
- Create: `mobileapp_poc/lib/ble_constants.dart`
- Create: `mobileapp_poc/lib/models/telemetry_data.dart`
- Test: `mobileapp_poc/test/models/telemetry_data_test.dart`

**Interfaces:**
- Produces: `TelemetryData` class with fields `double temp`, `double hum`, `int batt`; `TelemetryData.fromJson(String jsonStr)` factory; `String toJson()` method. Also produces `BleConstants` with `serviceUuid`, `telemetryCharUuid`, `controlCharUuid`, `deviceName` as `String` constants.

- [ ] **Step 1: Write the failing test**

Create `mobileapp_poc/test/models/telemetry_data_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobileapp_poc && flutter test test/models/telemetry_data_test.dart`
Expected: FAIL — `package:mobileapp_poc/models/telemetry_data.dart` does not exist.

- [ ] **Step 3: Write ble_constants.dart**

Create `mobileapp_poc/lib/ble_constants.dart`:

```dart
class BleConstants {
  static const String serviceUuid = '12345678-1234-5678-1234-56789abc0000';
  static const String telemetryCharUuid = '12345678-1234-5678-1234-56789abc0001';
  static const String controlCharUuid = '12345678-1234-5678-1234-56789abc0002';
  static const String deviceName = 'XIAO-POC';
}
```

- [ ] **Step 4: Write minimal implementation**

Create `mobileapp_poc/lib/models/telemetry_data.dart`:

```dart
import 'dart:convert';

class TelemetryData {
  final double temp;
  final double hum;
  final int batt;

  const TelemetryData({required this.temp, required this.hum, required this.batt});

  factory TelemetryData.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return TelemetryData(
      temp: (map['temp'] as num).toDouble(),
      hum: (map['hum'] as num).toDouble(),
      batt: (map['batt'] as num).toInt(),
    );
  }

  String toJson() => jsonEncode({'temp': temp, 'hum': hum, 'batt': batt});
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd mobileapp_poc && flutter test test/models/telemetry_data_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add mobileapp_poc/lib/ble_constants.dart mobileapp_poc/lib/models/telemetry_data.dart mobileapp_poc/test/models/telemetry_data_test.dart
git commit -m "Add BLE constants and TelemetryData model with tests"
```

---

### Task 3: ControlData model (TDD)

**Files:**
- Create: `mobileapp_poc/lib/models/control_data.dart`
- Test: `mobileapp_poc/test/models/control_data_test.dart`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `ControlData` class with fields `double setpoint`, `bool relay`; `ControlData.fromJson(String jsonStr)` factory; `String toJson()` method.

- [ ] **Step 1: Write the failing test**

Create `mobileapp_poc/test/models/control_data_test.dart`:

```dart
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobileapp_poc && flutter test test/models/control_data_test.dart`
Expected: FAIL — `package:mobileapp_poc/models/control_data.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `mobileapp_poc/lib/models/control_data.dart`:

```dart
import 'dart:convert';

class ControlData {
  final double setpoint;
  final bool relay;

  const ControlData({required this.setpoint, required this.relay});

  factory ControlData.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return ControlData(
      setpoint: (map['setpoint'] as num).toDouble(),
      relay: map['relay'] as bool,
    );
  }

  String toJson() => jsonEncode({'setpoint': setpoint, 'relay': relay});
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobileapp_poc && flutter test test/models/control_data_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add mobileapp_poc/lib/models/control_data.dart mobileapp_poc/test/models/control_data_test.dart
git commit -m "Add ControlData model with tests"
```

---

### Task 4: BleService (scan, connect, telemetry stream, control write)

**Files:**
- Create: `mobileapp_poc/lib/services/ble_service.dart`

**Interfaces:**
- Consumes: `BleConstants` (`lib/ble_constants.dart`), `TelemetryData` (`lib/models/telemetry_data.dart`), `ControlData` (`lib/models/control_data.dart`).
- Produces:
  - `BleService.requestPermissions() → Future<bool>`
  - `BleService.scan() → Stream<List<ScanResult>>` (re-exports `flutter_blue_plus`'s `ScanResult`)
  - `BleService.connect(BluetoothDevice device) → Future<void>`
  - `BleService.telemetryStream → Stream<TelemetryData>`
  - `BleService.connectionStateStream → Stream<BluetoothConnectionState>`
  - `BleService.readControl() → Future<ControlData>`
  - `BleService.writeControl(ControlData data) → Future<void>`
  - `BleService.disconnect() → Future<void>`

This task has no automated test — `flutter_blue_plus` requires a real BLE radio and cannot be meaningfully unit-tested. Correctness is verified manually in Task 8's end-to-end test, after the firmware (Task 7) exists.

- [ ] **Step 1: Write BleService**

Create `mobileapp_poc/lib/services/ble_service.dart`:

```dart
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
```

- [ ] **Step 2: Verify it compiles**

Run: `cd mobileapp_poc && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add mobileapp_poc/lib/services/ble_service.dart
git commit -m "Add BleService wrapping flutter_blue_plus scan/connect/notify/write"
```

---

### Task 5: ScanScreen

**Files:**
- Create: `mobileapp_poc/lib/screens/scan_screen.dart`

**Interfaces:**
- Consumes: `BleService` (`lib/services/ble_service.dart`) — `requestPermissions()`, `scan()`, `connect(device)`.
- Produces: `ScanScreen` widget (`StatefulWidget`), constructor `ScanScreen({required BleService bleService, super.key})`. On successful connect, navigates to `DashboardScreen` (built in Task 6) passing the same `BleService` instance.

- [ ] **Step 1: Write ScanScreen**

Create `mobileapp_poc/lib/screens/scan_screen.dart`:

```dart
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
```

- [ ] **Step 2: Verify it compiles**

Run: `cd mobileapp_poc && flutter analyze`
Expected: error referencing missing `dashboard_screen.dart` — expected at this point, resolved in Task 6.

- [ ] **Step 3: Commit**

```bash
git add mobileapp_poc/lib/screens/scan_screen.dart
git commit -m "Add ScanScreen for BLE device discovery"
```

---

### Task 6: DashboardScreen and app entry point

**Files:**
- Create: `mobileapp_poc/lib/screens/dashboard_screen.dart`
- Modify: `mobileapp_poc/lib/main.dart`

**Interfaces:**
- Consumes: `BleService` (`lib/services/ble_service.dart`), `TelemetryData`, `ControlData`, `ScanScreen` (`lib/screens/scan_screen.dart`).
- Produces: `DashboardScreen` widget, constructor `DashboardScreen({required BleService bleService, super.key})`. App entry point wires `ScanScreen` as the home screen with a fresh `BleService`.

- [ ] **Step 1: Write DashboardScreen**

Create `mobileapp_poc/lib/screens/dashboard_screen.dart`:

```dart
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
```

- [ ] **Step 2: Wire up main.dart**

Replace the contents of `mobileapp_poc/lib/main.dart`:

```dart
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
```

- [ ] **Step 3: Verify it compiles**

Run: `cd mobileapp_poc && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 4: Run the full model test suite**

Run: `cd mobileapp_poc && flutter test`
Expected: PASS (6 tests total — 3 from TelemetryData, 3 from ControlData)

- [ ] **Step 5: Commit**

```bash
git add mobileapp_poc/lib/screens/dashboard_screen.dart mobileapp_poc/lib/main.dart
git commit -m "Add DashboardScreen and wire up app entry point"
```

---

### Task 7: Arduino firmware sketch

**Files:**
- Create: `firmware/xiao_ble_poc/xiao_ble_poc.ino`

**Interfaces:**
- Produces: a flashable sketch implementing the GATT profile from Global Constraints — no code dependency on the Flutter app, only on the shared UUID/JSON contract.

**Prerequisite (one-time Arduino IDE setup, not scripted):** In Arduino IDE Boards Manager, install "Seeed nRF52 mbed-enabled Boards", then select board "Seeed XIAO nRF52840 Sense (mbed-enabled)". In Library Manager, install "ArduinoBLE" and "ArduinoJson".

- [ ] **Step 1: Write the firmware sketch**

Create `firmware/xiao_ble_poc/xiao_ble_poc.ino`:

```cpp
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
    return;
  }

  setpoint = doc["setpoint"] | setpoint;
  relayOn = doc["relay"] | relayOn;
  digitalWrite(LED_BUILTIN, relayOn ? LOW : HIGH); // LED_BUILTIN is active-low on XIAO nRF52840

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
```

- [ ] **Step 2: Flash and verify via Serial monitor**

Flash the sketch to the Seeed XIAO nRF52840 Sense (Arduino IDE → Upload). Open the Serial Monitor at 115200 baud.
Expected output: `XIAO-POC advertising` printed once at boot.

- [ ] **Step 3: Verify advertising with a BLE scanner app**

Using the nRF Connect app (or similar) on a phone, scan for BLE devices.
Expected: `XIAO-POC` appears in the scan list, with the custom service UUID `12345678-1234-5678-1234-56789abc0000` visible after connecting.

- [ ] **Step 4: Commit**

```bash
git add firmware/xiao_ble_poc/xiao_ble_poc.ino
git commit -m "Add Arduino BLE firmware for XIAO nRF52840 Sense"
```

---

### Task 8: End-to-end manual test

**Files:** none (verification task only)

**Interfaces:** Consumes the complete system from Tasks 1–7.

- [ ] **Step 1: Flash firmware**

Ensure the sketch from Task 7 is flashed and running on the Seeed XIAO nRF52840 Sense (LED off, Serial monitor shows "XIAO-POC advertising").

- [ ] **Step 2: Run the app on Android**

Run: `cd mobileapp_poc && flutter run -d <android-device-id>`
Expected: ScanScreen opens, permission prompts appear and are grantable, `XIAO-POC` appears in the scan list within ~10 seconds.

- [ ] **Step 3: Connect and verify telemetry**

Tap `XIAO-POC` in the list.
Expected: navigates to DashboardScreen; Temperature/Humidity/Battery values appear and update roughly once per second.

- [ ] **Step 4: Send a control update**

Enter a new setpoint value (e.g. `27.5`), toggle the Relay switch on, tap Send.
Expected: no error shown in the app; the firmware's Serial monitor prints `Received setpoint=27.50 relay=1`; the onboard LED turns on.

- [ ] **Step 5: Verify disconnect handling**

Power off or move the XIAO device out of range.
Expected: app detects the disconnect, shows a "Device disconnected" snackbar, and returns to ScanScreen.

- [ ] **Step 6: Repeat on iOS**

Run: `cd mobileapp_poc && flutter run -d <ios-device-id>`
Repeat Steps 2–5 on a physical iPhone (BLE does not work in the iOS Simulator).
Expected: same behavior as Android.

- [ ] **Step 7: Record results**

Note the outcome of each step (pass/fail + any deviations) in the PR description or a comment on this plan file — no separate document needed for a POC.

---

## Self-Review Notes

- **Spec coverage:** Architecture (Task 1, 4-6), GATT profile/data flow (Global Constraints, Tasks 2-4, 7), Components (Tasks 2-7), Error handling — permission denied (Task 5 `_error` state), disconnect (Task 6 `connectionStateStream` listener), malformed JSON (Task 4 `BleService` try/catch), write failure (Task 6 `_sendControl` try/catch) — all covered. Testing (Tasks 2-3 unit tests, Task 8 manual script) — covered.
- **Placeholder scan:** No TBD/TODO markers; all steps carry complete code.
- **Type consistency:** `TelemetryData(temp, hum, batt)` and `ControlData(setpoint, relay)` field names/types match across Tasks 2, 3, 4, 6. `BleService` method names (`requestPermissions`, `scan`, `connect`, `telemetryStream`, `connectionStateStream`, `readControl`, `writeControl`, `disconnect`) match between their definition in Task 4 and usage in Tasks 5-6.
