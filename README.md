# Privastead Mobile Application

## Development - Getting Started

[Flutter Online Documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Custom Set Up (rough draft guide) (Android)

Should you wish to build the application yourself instead of using our pre-built versions, this aims to help you do so.
This assumes you have already followed the setup instructions in https://github.com/privastead/privastead/blob/main/HOW_TO.md

### Step 1: Clone the repository

### Step 2: Download Visual Studio Code

### Step 3: Open the repository within Visual Studio Code

### Step 4: Open the terminal within VSC and run 'flutter pub get' (downloads all the necessary packages)

### Step 5: Set up Flutter Fire (google's notification service within Flutter)

To accomplish this, see the official tutorial - https://firebase.google.com/docs/flutter/setup?platform=ios
Select only iOS and Android when asked for platforms to set up.
Move the firebase_options.dart file automatically generated from lib/ to lib/notifications/

### Step 6: Setup Rust Code for Android

cd rust/ (from main directory)
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
cargo ndk -o ../android/app/src/main/jniLibs build

### Step 6: Plug your device in to your computer. To verify, you should see it connected within Visual Studio Code (see bottom right corner)

### Step 7: Run command: flutter run in main repo directory (/)

## Debugging

Should you run into issues on Android with the app not updating after restarting flutter run, run the command flutter clean and try running it again.

