# Retail Suite Mobile (Android)

This folder contains the Flutter source code for the Android app.

The app matches the browser POS and adds:
- Barcode scanning (camera)
- Offline queued sales + auto-sync
- Bluetooth thermal receipt printing (ESC/POS)
- Stock view
- Transfer dispatch/receive
- Stock take start/count/finalize
- Reports summary

## Quick start

1) Create a new Flutter project (once)

```bash
flutter create retail_suite_mobile
cd retail_suite_mobile
```

2) Copy these files into that project
- Replace the generated `pubspec.yaml` with the one from this folder
- Replace the generated `lib/` folder with the one from this folder

3) Android permissions

In `android/app/src/main/AndroidManifest.xml`, add:

```xml
<uses-permission android:name="android.permission.CAMERA"/>

<!-- Bluetooth printing -->
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>

<!-- Android 12+ -->
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
```

4) Install dependencies + run

```bash
flutter pub get
flutter run
```

5) Configure Base URL in-app
- Open Settings tab → Server → Base URL
- Example: `https://yourdomain.com`

## Printer setup
1. Pair your printer in Android Bluetooth settings
2. In the app: Settings → Printer → Select printer
3. Use “Test print”

## Offline mode
- In Settings → Offline Cache, tap **Sync products**
- When internet goes down:
  - sales are queued locally
  - when internet returns, app auto-syncs queued sales
