#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FLUTTER_INPUT="${1:-flutter}"
REVIEW_PREVIEW_VIDEO="$REPO_ROOT/assets/design/review_front_door_preview.mp4"
REVIEW_PREVIEW_BACKUP=""

resolve_flutter_bin() {
  if [[ "$FLUTTER_INPUT" == */* ]]; then
    if [[ -x "$FLUTTER_INPUT" ]]; then
      printf '%s\n' "$FLUTTER_INPUT"
      return 0
    fi
    return 1
  fi
  command -v "$FLUTTER_INPUT" 2>/dev/null
}

read_local_properties_value() {
  local key="$1"
  local properties_file="$REPO_ROOT/android/local.properties"
  if [[ ! -f "$properties_file" ]]; then
    return 1
  fi
  sed -n "s/^${key}=//p" "$properties_file" | tail -n 1
}

detect_android_sdk() {
  if [[ -n "${ANDROID_HOME:-}" ]]; then
    printf '%s\n' "$ANDROID_HOME"
    return 0
  fi
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
    return 0
  fi

  local sdk_dir=""
  sdk_dir="$(read_local_properties_value "sdk.dir" || true)"
  if [[ -n "$sdk_dir" ]]; then
    printf '%s\n' "$sdk_dir"
    return 0
  fi

  if [[ -d "$HOME/Library/Android/sdk" ]]; then
    printf '%s\n' "$HOME/Library/Android/sdk"
    return 0
  fi
  if [[ -d "/opt/android-sdk" ]]; then
    printf '%s\n' "/opt/android-sdk"
    return 0
  fi
  return 1
}

FLUTTER_BIN="$(resolve_flutter_bin || true)"
if [[ -z "$FLUTTER_BIN" ]]; then
  cat >&2 <<EOF
Could not find Flutter binary: $FLUTTER_INPUT

For a local build, run one of:
  ./tool/fdroid/build_fdroid_apk.sh
  ./tool/fdroid/build_fdroid_apk.sh "/absolute/path/to/flutter/bin/flutter"

The string "\$\$flutter\$\$/bin/flutter" is only an fdroiddata placeholder.
Do not run that literal value in your local shell.
EOF
  exit 1
fi

ANDROID_HOME="$(detect_android_sdk || true)"
if [[ -z "$ANDROID_HOME" ]]; then
  cat >&2 <<EOF
Could not determine Android SDK location.

Set ANDROID_HOME or ANDROID_SDK_ROOT, or ensure android/local.properties contains sdk.dir.
EOF
  exit 1
fi

cleanup() {
  if [[ -n "$REVIEW_PREVIEW_BACKUP" && -f "$REVIEW_PREVIEW_BACKUP" ]]; then
    mv "$REVIEW_PREVIEW_BACKUP" "$REVIEW_PREVIEW_VIDEO"
  fi
}
trap cleanup EXIT

if [[ -f "$REVIEW_PREVIEW_VIDEO" ]]; then
  REVIEW_PREVIEW_BACKUP="$(mktemp "${TMPDIR:-/tmp}/secluso-fdroid-preview.XXXXXX.mp4")"
  mv "$REVIEW_PREVIEW_VIDEO" "$REVIEW_PREVIEW_BACKUP"
fi

export ANDROID_HOME
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export FLUTTER_HOME="${FLUTTER_HOME:-$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)}"
export PATH="$FLUTTER_HOME/bin:$PATH"
export PUB_CACHE="${PUB_CACHE:-$REPO_ROOT/.pub-cache}"
export SECLUSO_FDROID_BUILD=1
export SECLUSO_REPRO_CLEAN="${SECLUSO_REPRO_CLEAN:-1}"

"$FLUTTER_BIN" config --no-analytics
"$REPO_ROOT/tool/repro/build_unsigned_android_release.sh"
