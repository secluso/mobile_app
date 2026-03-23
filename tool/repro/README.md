# Android Reproducible Builds

This folder is the Android reproducible build setup for the Secluso mobile app.
The basic idea came from the Telegram reproducible builds page:

- https://core.telegram.org/reproducible-builds

The short version is that this folder gives us a pinned Docker build environment, a way to rebuild the Android APK in that environment, and a way to compare the rebuilt APK against either another rebuild or an APK pulled from a phone.

The most basic command is:

```bash
tool/repro/build_with_docker.sh
```

That builds the unsigned Android release APK in Docker and puts it here:

```text
build/reproducible/app-release-unsigned.apk
```

If you want to check whether the build is actually reproducible, run:

```bash
tool/repro/check_reproducibility.sh
```

That script makes two fresh copies of the workspace under `/tmp`, builds the app twice in the same pinned Docker setup, and compares the two APKs. If it works, both the file comparison and the SHA-256 hashes should match.

If you want to compare against a Secluso APK installed on a phone, the flow is also pretty simple. First rebuild the unsigned APK:

```bash
tool/repro/build_with_docker.sh
```

Then make sure adb sees the device:

```bash
adb devices
```

After that, just run:

```bash
tool/repro/compare_with_device.sh
```

For signed releases, the intended model is to build the canonical unsigned APK first and sign it after that. That keeps the reproducible part and the signing part separate.

The official signed-release flow is:

```bash
SECLUSO_ANDROID_SIGNING_DIR=/path/to/signing-material \
tool/repro/build_official_release_with_docker.sh
```

That signing directory needs:

- key.properties
- the keystore file referenced by storeFile

The signed release flow writes:

```text
build/reproducible/app-release-unsigned.apk
build/reproducible/app-release-signed.apk
build/reproducible/app-release-signed.apk.sha256
```

One thing that might happen is that the build fails at flutter pub get --enforce-lockfile. If that happens, it means the committed pubspec.lock no longer matches what the pinned Docker toolchain resolves for the current pubspec.yaml. In that case, update the lockfile with:

```bash
tool/repro/update_lockfile_with_docker.sh
```

Then review the pubspec.lock diff, commit it, and rerun the reproducibility check.

There are a few limits to keep in mind. This setup is mainly for direct APK verification, where the installed app corresponds to one base.apk. It is not the full Google Play split APK or AAB verification (yet) - we cannot fully verify this until the app is published. Also, the APK comparison intentionally ignores signing metadata files under META-INF, because the point is to compare the app payload, not the certificate wrapper around it.

That is the main idea.