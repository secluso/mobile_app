#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ ! -f "$REPO_ROOT/pubspec.yaml" ]]; then
  echo "Expected Flutter project root at $REPO_ROOT" >&2
  exit 1
fi

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export TZ=UTC

export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export CARGO_HOME="${CARGO_HOME:-/opt/cargo}"
export FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/opt/gradle-home}"
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.daemon=false -Dorg.gradle.parallel=false -Dorg.gradle.vfs.watch=false -Dorg.gradle.workers.max=1 -Dkotlin.compiler.execution.strategy=in-process"
export PUB_CACHE="${PUB_CACHE:-/opt/pub-cache}"
export RUSTUP_HOME="${RUSTUP_HOME:-/opt/rustup}"
export CARGOKIT_RUST_TOOLCHAIN="${CARGOKIT_RUST_TOOLCHAIN:-1.90.0}"
export SECLUSO_FLUTTER_VERBOSE="${SECLUSO_FLUTTER_VERBOSE:-0}"
export SECLUSO_ANDROID_TARGET_PLATFORM="${SECLUSO_ANDROID_TARGET_PLATFORM:-android-arm64}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-1}"
export CARGO_INCREMENTAL=0
export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$CARGO_HOME/bin:$PATH"

if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
  if git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
    SOURCE_DATE_EPOCH="$(git -C "$REPO_ROOT" log -1 --format=%ct)"
  else
    SOURCE_DATE_EPOCH="1704067200"
  fi
fi
export SOURCE_DATE_EPOCH

mkdir -p "$ANDROID_HOME" "$CARGO_HOME" "$GRADLE_USER_HOME" "$PUB_CACHE" "$RUSTUP_HOME"

log_step() {
  printf '\n==> %s\n' "$1"
}

cat > "$REPO_ROOT/android/local.properties" <<EOF
sdk.dir=$ANDROID_HOME
flutter.sdk=$FLUTTER_HOME
EOF

log_step "Cleaning prior build outputs"
rm -rf \
  "$REPO_ROOT/.dart_tool" \
  "$REPO_ROOT/build" \
  "$REPO_ROOT/rust/target"

cd "$REPO_ROOT"
log_step "Running flutter pub get"
flutter pub get --enforce-lockfile

export SECLUSO_ALLOW_UNSIGNED_RELEASE=1
log_step "Building Android release APK"
if [[ "$SECLUSO_FLUTTER_VERBOSE" == "1" ]]; then
  flutter build apk --release --no-pub --target-platform="$SECLUSO_ANDROID_TARGET_PLATFORM" -v
else
  flutter build apk --release --no-pub --target-platform="$SECLUSO_ANDROID_TARGET_PLATFORM"
fi

OUTPUT_DIR="$REPO_ROOT/build/reproducible"
mkdir -p "$OUTPUT_DIR"
log_step "Collecting reproducible build artifact"
cp "$REPO_ROOT/build/app/outputs/flutter-apk/app-release.apk" \
  "$OUTPUT_DIR/app-release-unsigned.apk"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUTPUT_DIR/app-release-unsigned.apk" \
    | tee "$OUTPUT_DIR/app-release-unsigned.apk.sha256"
else
  shasum -a 256 "$OUTPUT_DIR/app-release-unsigned.apk" \
    | tee "$OUTPUT_DIR/app-release-unsigned.apk.sha256"
fi
