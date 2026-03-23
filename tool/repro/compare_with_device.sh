#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKAGE_NAME="${1:-com.secluso.mobile}"
DEVICE_APK_PATH="$REPO_ROOT/build/reproducible/device.apk"
BUILT_APK_PATH="$REPO_ROOT/build/reproducible/app-release-unsigned.apk"

"$SCRIPT_DIR/pull_device_apk.sh" "$PACKAGE_NAME" "$DEVICE_APK_PATH"

if [[ ! -f "$BUILT_APK_PATH" ]]; then
  echo "Built APK not found at $BUILT_APK_PATH" >&2
  echo "Run tool/repro/build_with_docker.sh first." >&2
  exit 1
fi

python3 "$SCRIPT_DIR/apkdiff.py" "$DEVICE_APK_PATH" "$BUILT_APK_PATH"
