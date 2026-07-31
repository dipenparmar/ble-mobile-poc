# BLE Dashboard POC — Design

## Purpose

Prove out a Flutter mobile app talking to a Seeed XIAO nRF52840 Sense over BLE,
exchanging 5 parameters (3 telemetry + 2 control) for a local, real-time
dashboard. No cloud, no persistence — a wiring/protocol proof, not a product.

## Scope

- 1 BLE peripheral (Arduino firmware), 1 Flutter app (Android + iOS).
- 5 parameters total: temperature, humidity, battery (device → app, notified),
  setpoint, relay (app → device, written).
- Manual scan + connect flow (no auto-connect, no multi-device management).
- Simulated telemetry values in firmware (no real sensors wired up); onboard
  LED stands in for a physical relay.

## Architecture

Two independent components connected only by the BLE GATT profile below:

- **Firmware** — `firmware/xiao_ble_poc/xiao_ble_poc.ino`, Arduino sketch for
  the Seeed XIAO nRF52840 Sense, built on the **mbed-enabled** Seeed nRF52
  board package so the standard `ArduinoBLE` library is available. Advertises
  as `"XIAO-POC"`. A 1Hz timer updates the Telemetry characteristic and
  notifies. A write callback on the Control characteristic parses incoming
  JSON, stores the setpoint, and drives the onboard LED from the relay flag.
- **Flutter app** — `mobileapp_poc/`, single project targeting Android and
  iOS, using `flutter_blue_plus`. A `BleService` class wraps scan / connect /
  notify-stream / write. State management is plain `StatefulWidget` +
  `StreamSubscription` — no Provider/Riverpod/Bloc, this is a single-screen
  POC.
  - `ScanScreen` — lists nearby BLE devices (name + RSSI), tap to connect.
  - `DashboardScreen` — shows live telemetry, a setpoint text field + Send
    button, and a relay toggle switch.

## GATT Profile & Data Flow

```
Service UUID:    12345678-1234-5678-1234-56789abc0000  (custom, POC-only)
Telemetry Char:  12345678-1234-5678-1234-56789abc0001  (Read, Notify)
Control Char:    12345678-1234-5678-1234-56789abc0002  (Read, Write)
```

Both characteristics carry a JSON string as UTF-8 bytes (not packed binary) —
chosen for easy debugging with any BLE scanner (e.g. nRF Connect) and trivial
parsing on both the Arduino and Dart sides.

Telemetry (firmware → app, notified ~1/sec):
```json
{"temp": 23.5, "hum": 61.2, "batt": 87}
```

Control (app → firmware, written on user action):
```json
{"setpoint": 25.0, "relay": true}
```

Sequence:
1. App connects, discovers services.
2. App reads Control once to show the firmware's current state.
3. App subscribes to Telemetry notifications.
4. Firmware pushes a Telemetry JSON blob every ~1s; app parses and updates
   the dashboard.
5. When the user edits the setpoint or flips the relay switch, the app writes
   the **full** Control JSON blob (both fields together — simplest to parse,
   avoids partial-update ambiguity). Firmware parses it, updates its setpoint
   variable and LED state, and keeps its own Control characteristic value in
   sync so a future read stays consistent.

## Components

**Firmware side:**
- BLE peripheral setup: advertising, service/characteristic registration
  (ArduinoBLE, mbed-enabled core).
- Telemetry generator: 1Hz timer producing simulated temp/humidity/battery
  values (temperature may use the nRF52840's onboard die temperature sensor
  as one real-ish value; humidity/battery are simple simulated patterns).
- Control write handler: parses incoming JSON, updates the stored setpoint,
  and drives the onboard LED from the relay flag. Echoes received values to
  Serial for manual verification during testing.

**Flutter side:**
- `BleService` — wraps `flutter_blue_plus`: `scan()`, `connect(device)`,
  a `telemetryStream`, and `writeControl(setpoint, relay)`.
- `TelemetryData` / `ControlData` — plain Dart models with `fromJson`/
  `toJson`, no BLE dependency (independently unit-testable).
- `ScanScreen` — device discovery list UI.
- `DashboardScreen` — telemetry display + setpoint field + relay switch.

## Error Handling

- **Bluetooth/Location permission denied** — show an in-app message, don't
  crash; user can retry from the scan screen.
- **Disconnect mid-session** — app detects the plugin's disconnect event and
  returns to the scan screen with a "Device disconnected" notice.
- **Malformed JSON on notify** — parse error is caught and logged; that
  update is skipped and the last-known values remain displayed. No
  retry/backoff logic — POC scope only.
- **Write failure** — surfaced as a snackbar error, no auto-retry.

## Testing

Hardware-dependent, so no automated BLE integration tests.

- Unit tests for `TelemetryData`/`ControlData` JSON encode/decode — pure
  Dart, no hardware required.
- Manual test script:
  1. Flash firmware to the Seeed XIAO nRF52840 Sense.
  2. Run the app on an Android device; confirm scan finds `XIAO-POC`.
  3. Connect; confirm telemetry values update roughly once per second.
  4. Send a setpoint value and toggle the relay switch; confirm the
     firmware's Serial monitor shows the received values and the onboard LED
     toggles accordingly.
  5. Repeat steps 2–4 on an iOS device.

## Out of Scope

- Real sensors (temperature/humidity hardware), real relay hardware.
- Auto-reconnect, multi-device management, background BLE operation.
- Any cloud sync, local persistence, or historical data/charts.
- Automated BLE integration testing (manual test script only).
