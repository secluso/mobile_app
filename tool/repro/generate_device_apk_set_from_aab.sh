#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUNDLETOOL_JAR="${BUNDLETOOL_JAR:-/opt/bundletool.jar}"
INPUT_AAB="${1:-${INPUT_AAB:-$REPO_ROOT/build/reproducible/app-release-unsigned.aab}}"
DEVICE_SPEC_JSON="${2:-${SECLUSO_DEVICE_SPEC_JSON:-}}"
OUTPUT_APKS="${3:-${OUTPUT_APKS:-$REPO_ROOT/build/reproducible/device.apks}}"
SIGNING_DIR="${SECLUSO_ANDROID_SIGNING_DIR:-}"

if [[ ! -f "$INPUT_AAB" ]]; then
  echo "Input AAB not found at $INPUT_AAB" >&2
  exit 1
fi

if [[ -z "$DEVICE_SPEC_JSON" ]]; then
  echo "Usage: $(basename "$0") [input.aab] <device-spec.json> [output.apks]" >&2
  echo "Provide the device spec as the second argument or set SECLUSO_DEVICE_SPEC_JSON." >&2
  exit 1
fi

if [[ ! -f "$DEVICE_SPEC_JSON" ]]; then
  echo "Device spec JSON not found at $DEVICE_SPEC_JSON" >&2
  exit 1
fi

if [[ ! -f "$BUNDLETOOL_JAR" ]]; then
  echo "bundletool jar not found at $BUNDLETOOL_JAR" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_APKS")"

command=(
  java -jar "$BUNDLETOOL_JAR" build-apks
  "--bundle=$INPUT_AAB"
  "--device-spec=$DEVICE_SPEC_JSON"
  "--output=$OUTPUT_APKS"
  --overwrite
)

if [[ -n "$SIGNING_DIR" ]]; then
  KEY_PROPERTIES_FILE="$SIGNING_DIR/key.properties"
  if [[ ! -f "$KEY_PROPERTIES_FILE" ]]; then
    echo "Missing key.properties in $SIGNING_DIR" >&2
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

  command+=(
    "--ks=$STORE_FILE"
    "--ks-pass=pass:$STORE_PASSWORD"
    "--ks-key-alias=$KEY_ALIAS"
    "--key-pass=pass:$KEY_PASSWORD"
  )
else
  echo "No SECLUSO_ANDROID_SIGNING_DIR provided. bundletool will use its debug signing path."
fi

"${command[@]}"
echo "Wrote device-targeted APK set to $OUTPUT_APKS"
