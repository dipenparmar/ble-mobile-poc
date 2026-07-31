# BLE Mobile POC

A proof-of-concept BLE dashboard: a Flutter app (Android + iOS) that connects
to a Seeed XIAO nRF52840 Sense running custom Arduino firmware, receiving 3
live telemetry values (temperature, humidity, battery) and sending 2 control
values (setpoint, relay) — all over a custom BLE GATT profile.

```
firmware/xiao_ble_poc/xiao_ble_poc.ino   Arduino sketch (BLE peripheral)
mobileapp_poc/                           Flutter app (BLE central)
docs/superpowers/specs/                  Design spec
docs/superpowers/plans/                  Implementation plan
```

## GATT Profile

| | UUID | Properties | JSON payload |
|---|---|---|---|
| Service | `12345678-1234-5678-1234-56789abc0000` | | |
| Telemetry | `12345678-1234-5678-1234-56789abc0001` | Read, Notify | `{"temp": <double>, "hum": <double>, "batt": <int>}` |
| Control | `12345678-1234-5678-1234-56789abc0002` | Read, Write | `{"setpoint": <double>, "relay": <bool>}` |

The device advertises as **`XIAO-POC`**. Both characteristics carry JSON as
plain UTF-8 text (not packed binary), so you can inspect traffic with any
generic BLE scanner app (e.g. nRF Connect).

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (developed against 3.44.x)
- A Seeed XIAO nRF52840 Sense board + USB-C cable
- [Arduino IDE](https://www.arduino.cc/en/software) 2.x
- For iOS: a Mac with Xcode, and a physical iPhone (BLE does not work in the iOS Simulator)
- For Android: a physical Android device (BLE does not work in most emulators either)

## 1. Flash the firmware

1. In Arduino IDE, open **Boards Manager** (left sidebar) and install
   **"Seeed nRF52 mbed-enabled Boards"**.
2. In **Tools → Board**, select **Seeed XIAO nRF52840 Sense (mbed-enabled)**.
   Using the non-mbed "Seeed nRF52 Boards" package instead will NOT work —
   the sketch depends on the `ArduinoBLE` API, which requires the
   mbed-enabled core.
3. In **Library Manager**, install:
   - **ArduinoBLE**
   - **ArduinoJson**
4. Open `firmware/xiao_ble_poc/xiao_ble_poc.ino`, connect the board over
   USB, select the correct port in **Tools → Port**, and click **Upload**.
5. Open the Serial Monitor at **115200 baud**. You should see:
   ```
   XIAO-POC advertising
   ```

## 2. Run the Flutter app

```bash
cd mobileapp_poc
flutter pub get
```

### Android

```bash
flutter devices        # confirm your device is listed
flutter run -d <device-id>
```

Grant the Bluetooth permission prompt when it appears. The app requires
Android 12+ (`minSdk 31`).

### iOS (physical device required)

BLE cannot be tested in the iOS Simulator — you need a real iPhone connected
to your Mac.

1. **Open the iOS project in Xcode**, not just the Flutter CLI, the first
   time — this lets you configure code signing:
   ```bash
   open ios/Runner.xcworkspace
   ```
   (If `Runner.xcworkspace` doesn't exist yet, run `flutter build ios --no-codesign`
   once first — this generates the CocoaPods workspace by installing the
   `flutter_blue_plus` and `permission_handler` iOS pod dependencies.)

2. **Select your Team for code signing:**
   - In Xcode's left sidebar, click the **Runner** project → **Runner** target
     → **Signing & Capabilities** tab.
   - Under **Team**, choose your Apple ID (add one via **Xcode → Settings →
     Accounts** if none is listed — a free Apple ID works fine for
     development/testing, no paid developer account required).
   - If you see a "Bundle Identifier is not available" error, change
     `PRODUCT_BUNDLE_IDENTIFIER` (same screen) from `com.example.mobileappPoc`
     to something unique, e.g. `com.<yourname>.blemobilepoc`.

3. **Connect your iPhone** via USB (or pair it wirelessly in Xcode's Devices
   window) and unlock it.

4. **Trust your Mac on the iPhone** if prompted ("Trust This Computer?").

5. **Run the app** — either from Xcode (select your iPhone as the run
   destination, press ▶) or from the CLI:
   ```bash
   flutter devices        # confirm your iPhone is listed
   flutter run -d <device-id>
   ```

6. **First launch only:** iOS will refuse to run an app signed with a free
   developer account until you explicitly trust it. On the iPhone, go to
   **Settings → General → VPN & Device Management**, find your Apple ID
   under "Developer App", and tap **Trust**.

7. The app will prompt for Bluetooth permission (via the
   `NSBluetoothAlwaysUsageDescription` string already configured in
   `Info.plist`) — allow it.

   > Free Apple ID builds expire after 7 days — you'll need to re-run
   > `flutter run` (or re-build from Xcode) to reinstall after that.

### Using the app

1. On launch, the app scans for nearby BLE devices — tap **`XIAO-POC`** in
   the list to connect.
2. The dashboard shows live temperature/humidity/battery, updating roughly
   once per second.
3. Enter a setpoint value and/or toggle the relay switch, then tap **Send**
   — check the firmware's Serial Monitor output to confirm it received the
   update, and watch the board's onboard LED toggle with the relay switch.

## Troubleshooting

- **App won't compile for iOS / missing `Runner.xcworkspace`:** run
  `flutter build ios --no-codesign` once to trigger CocoaPods install.
- **"Untrusted Developer" on iPhone:** see step 6 above.
- **Scan finds nothing:** confirm the firmware's Serial Monitor still shows
  `XIAO-POC advertising`, and that Bluetooth is on for both the phone and
  the board.
- **Telemetry doesn't update:** the firmware notifies at whole-number JSON
  values, e.g. `{"temp":20,"hum":50,"batt":100}` — this is correctly handled
  in the Dart models, but if you customize the firmware, keep to numeric
  JSON that fits within the control characteristic's 64-byte buffer.
