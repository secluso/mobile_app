#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

UNSIGNED_APK="${UNSIGNED_APK:-$REPO_ROOT/build/reproducible/app-release-unsigned.apk}"
SIGNED_APK="${SIGNED_APK:-$REPO_ROOT/build/reproducible/app-release-signed.apk}"
SIGNING_DIR="${SECLUSO_ANDROID_SIGNING_DIR:-}"
ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
BUILD_TOOLS_VERSION="${SECLUSO_ANDROID_BUILD_TOOLS_VERSION:-34.0.0}"

if [[ -z "$SIGNING_DIR" ]]; then
  echo "SECLUSO_ANDROID_SIGNING_DIR is required" >&2
  exit 1
fi

KEY_PROPERTIES_FILE="$SIGNING_DIR/key.properties"
if [[ ! -f "$KEY_PROPERTIES_FILE" ]]; then
  echo "Missing key.properties in $SIGNING_DIR" >&2
  exit 1
fi

if [[ ! -f "$UNSIGNED_APK" ]]; then
  echo "Unsigned APK not found at $UNSIGNED_APK" >&2
  exit 1
fi

read_property() {
  local key="$1"
  sed -n "s/^${key}=//p" "$KEY_PROPERTIES_FILE" | tail -n 1
}

STORE_FILE="$(read_property storeFile)"
STORE_PASSWORD="$(read_property storePassword)"
KEY_ALIAS="$(read_property keyAlias)"
KEY_PASSWORD="$(read_property keyPassword)"

if [[ -z "$STORE_FILE" || -z "$STORE_PASSWORD" || -z "$KEY_ALIAS" || -z "$KEY_PASSWORD" ]]; then
  echo "key.properties must include storeFile, storePassword, keyAlias, and keyPassword" >&2
  exit 1
fi

if [[ "$STORE_FILE" != /* ]]; then
  STORE_FILE="$SIGNING_DIR/$STORE_FILE"
fi

if [[ ! -f "$STORE_FILE" ]]; then
  echo "Keystore not found at $STORE_FILE" >&2
  exit 1
fi

ZIPALIGN="$ANDROID_HOME/build-tools/$BUILD_TOOLS_VERSION/zipalign"
APKSIGNER="$ANDROID_HOME/build-tools/$BUILD_TOOLS_VERSION/apksigner"

if [[ ! -x "$ZIPALIGN" || ! -x "$APKSIGNER" ]]; then
  echo "Expected zipalign and apksigner under $ANDROID_HOME/build-tools/$BUILD_TOOLS_VERSION" >&2
  exit 1
fi

TMP_ALIGNED_APK="$(mktemp "${TMPDIR:-/tmp}/secluso-aligned.XXXXXX.apk")"
trap 'rm -f "$TMP_ALIGNED_APK"' EXIT

mkdir -p "$(dirname "$SIGNED_APK")"

"$ZIPALIGN" -f -p 4 "$UNSIGNED_APK" "$TMP_ALIGNED_APK"
"$APKSIGNER" sign \
  --ks "$STORE_FILE" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass "pass:$STORE_PASSWORD" \
  --key-pass "pass:$KEY_PASSWORD" \
  --out "$SIGNED_APK" \
  "$TMP_ALIGNED_APK"
"$APKSIGNER" verify "$SIGNED_APK"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$SIGNED_APK" | tee "$SIGNED_APK.sha256"
else
  shasum -a 256 "$SIGNED_APK" | tee "$SIGNED_APK.sha256"
fi
