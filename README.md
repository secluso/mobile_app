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

> Need help or want to contribute? Visit the [Secluso GitHub Repository](https://github.com/secluso/secluso).
