#!/usr/bin/env bash
set -euo pipefail

FLUTTER_BIN="${1:-flutter}"

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

"$FLUTTER_BIN" config --no-analytics
"$FLUTTER_BIN" pub get
SECLUSO_ALLOW_UNSIGNED_RELEASE=1 \
  "$FLUTTER_BIN" build apk --release --dart-define=SECLUSO_FDROID_BUILD=true
