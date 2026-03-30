#!/usr/bin/env bash
set -euo pipefail

FLUTTER_BIN="${1:-flutter}"
REVIEW_PREVIEW_VIDEO="assets/design/review_front_door_preview.mp4"
REVIEW_PREVIEW_BACKUP=""

if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  cat >&2 <<EOF
Could not find Flutter binary: $FLUTTER_BIN

For a local build, run one of:
  ./tool/fdroid/build_fdroid_apk.sh
  ./tool/fdroid/build_fdroid_apk.sh "/absolute/path/to/flutter/bin/flutter"

The string "\$\$flutter\$\$/bin/flutter" is only an fdroiddata placeholder.
Do not run that literal value in your local shell.
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

"$FLUTTER_BIN" config --no-analytics
"$FLUTTER_BIN" pub get
SECLUSO_ALLOW_UNSIGNED_RELEASE=1 \
  "$FLUTTER_BIN" build apk --release --dart-define=SECLUSO_FDROID_BUILD=true
