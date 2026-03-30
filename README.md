# Secluso Mobile Application  
**Developer Quick-Start Guide (Android & iOS)**

> Use this guide to build the Secluso mobile application from source.  
> Important: Complete all core setup steps in [`HOW_TO.md`](https://github.com/secluso/secluso/blob/main/HOW_TO.md) before continuing.

---

## 1. Reference Documentation

- **Flutter Docs:** [flutter.dev](https://docs.flutter.dev/)
- **Firebase Setup for Flutter:** [firebase.google.com/docs/flutter/setup](https://firebase.google.com/docs/flutter/setup?platform=ios)

---

## 2. Prerequisites

Make sure the following tools are installed:

| Tool | Purpose |
|------|---------|
| Flutter SDK (3.x or later) | Cross-platform mobile framework |
| Rust + rustup | Native library support |
| Android NDK | Compile Rust code for Android |
| Visual Studio Code | Recommended IDE |
| Firebase Account | Required for push notifications |

You can verify setup with `flutter doctor`.

---

## 3. Project Setup (Step-by-Step)

### 3.1 Clone the Repository

```
git clone https://github.com/secluso/secluso.git  
cd secluso
```

---

### 3.2 Open the Project in Visual Studio Code

- Launch Visual Studio Code
- Open the secluso/ folder  
- Install any recommended extensions (Flutter, Rust, Dart)

---

### 3.3 Install Flutter Packages

```
flutter pub get
```

---

## 4. Compile Rust Code for Android

From the project root:

```
cd rust
```

Add Android build targets:

```
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
```

Build and export to the Android JNI directory:

```
cargo ndk -o ../android/app/src/main/jniLibs build
```

This will generate .so files for each architecture and place them in the appropriate folder.

---

## 5. Run on a Physical Android Device

1. Plug in your Android device via USB
2. Enable Developer Mode and USB Debugging
3. Ensure the device is recognized in Visual Studio Code (bottom-right status bar)
4. From the project root, run:

```
flutter run
```

This will build and launch the app on your connected device.

---

## 6. Debugging Tips

| Problem | Solution |
|--------|----------|
| App doesn’t update after `flutter run` | Run `flutter clean` first |
| Rust compilation errors | Ensure targets and NDK are properly set 
---

## 7. Early-Stage Android Reproducible Build

The Android project includes a containerized reproducible-build path under tool/repro.

To compare an official Secluso Android release installed on a phone against a local rebuild:

```bash
tool/repro/build_with_docker.sh
tool/repro/pull_device_apk.sh
python3 tool/repro/apkdiff.py \
  build/reproducible/device.apk \
  build/reproducible/app-release-unsigned.apk
```

For the full reproducible-build workflow, signed-release path, and internal reproducibility test (`tool/repro/check_reproducibility.sh`), see `tool/repro/README.md`.

---

## 8. Special F-Droid Android Build

The app supports a special Android build mode for F-Droid that forces UnifiedPush and excludes Firebase from the Android dependency graph.

Build it with:

```bash
flutter build apk --dart-define=SECLUSO_FDROID_BUILD=true
```

What this does:

- Forces Android push transport to UnifiedPush
- Excludes the Android `firebase_core` and `firebase_messaging` plugin projects
- Excludes the direct native `com.google.firebase:firebase-messaging` dependency
- Generates an F-Droid-specific `GeneratedPluginRegistrant` without Firebase or `integration_test`

Important note:

- The Dart packages `firebase_core` and `firebase_messaging` still remain in `pubspec.yaml` for normal App Store / Play builds.
- That does not break the F-Droid build by itself. Flutter/Dart imports are resolved at the Dart package level, while Android plugin registration is a separate native step.
- In the F-Droid build, the Firebase Android plugins are not registered, and the Android push flow is routed through UnifiedPush instead of FCM.
- Because the F-Droid runtime avoids the FCM code paths, the remaining Dart imports do not trigger Firebase runtime errors on Android.

Verification commands:

```bash
SECLUSO_FDROID_BUILD=1 ./android/gradlew -p android app:properties --console=plain
SECLUSO_FDROID_BUILD=1 ./android/gradlew -p android app:dependencies --configuration debugRuntimeClasspath --console=plain
```

On the F-Droid build, the runtime classpath should include `project :unifiedpush_android` and should not include `firebase_core`, `firebase_messaging`, or `com.google.firebase:*`.

---

> Need help or want to contribute? Visit the [Secluso GitHub Repository](https://github.com/secluso/secluso).
