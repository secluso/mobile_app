#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKAGE_NAME="${1:-com.secluso.mobile}"
OUTPUT_PATH="${2:-$REPO_ROOT/build/reproducible/device.apk}"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

PACKAGE_PATHS="$(adb shell pm path "$PACKAGE_NAME" | tr -d '\r')"

if [[ -z "$PACKAGE_PATHS" ]]; then
  echo "Package not found on connected device: $PACKAGE_NAME" >&2
  exit 1
fi

BASE_PATH="$(printf '%s\n' "$PACKAGE_PATHS" | sed -n 's/^package://p' | grep '/base\.apk$' | head -n 1)"

if [[ -z "$BASE_PATH" ]]; then
  echo "Could not find base.apk for package: $PACKAGE_NAME" >&2
  echo "$PACKAGE_PATHS" >&2
  exit 1
fi

adb pull "$BASE_PATH" "$OUTPUT_PATH" >/dev/null
echo "Pulled $PACKAGE_NAME base APK to $OUTPUT_PATH"
