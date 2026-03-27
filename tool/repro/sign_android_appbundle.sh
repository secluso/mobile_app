#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

UNSIGNED_AAB="${UNSIGNED_AAB:-$REPO_ROOT/build/reproducible/app-release-unsigned.aab}"
SIGNED_AAB="${SIGNED_AAB:-$REPO_ROOT/build/reproducible/app-release-signed.aab}"
SIGNING_DIR="${SECLUSO_ANDROID_SIGNING_DIR:-}"
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"

if [[ -z "$SIGNING_DIR" ]]; then
  echo "SECLUSO_ANDROID_SIGNING_DIR is required" >&2
  exit 1
fi

KEY_PROPERTIES_FILE="$SIGNING_DIR/key.properties"
if [[ ! -f "$KEY_PROPERTIES_FILE" ]]; then
  echo "Missing key.properties in $SIGNING_DIR" >&2
  exit 1
fi

if [[ ! -f "$UNSIGNED_AAB" ]]; then
  echo "Unsigned AAB not found at $UNSIGNED_AAB" >&2
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

if [[ -x "$JAVA_HOME/bin/jarsigner" ]]; then
  JARSIGNER="$JAVA_HOME/bin/jarsigner"
elif command -v jarsigner >/dev/null 2>&1; then
  JARSIGNER="$(command -v jarsigner)"
else
  echo "jarsigner is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$SIGNED_AAB")"

"$JARSIGNER" \
  -keystore "$STORE_FILE" \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -signedjar "$SIGNED_AAB" \
  "$UNSIGNED_AAB" \
  "$KEY_ALIAS"

"$JARSIGNER" -verify "$SIGNED_AAB"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$SIGNED_AAB" | tee "$SIGNED_AAB.sha256"
else
  shasum -a 256 "$SIGNED_AAB" | tee "$SIGNED_AAB.sha256"
fi
