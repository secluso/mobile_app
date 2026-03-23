#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE_TAG="${SECLUSO_REPRO_IMAGE_TAG:-secluso-mobile-repro:local}"
DOCKER_PLATFORM="${SECLUSO_DOCKER_PLATFORM:-linux/amd64}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

docker build --platform "$DOCKER_PLATFORM" -f "$SCRIPT_DIR/Dockerfile" -t "$IMAGE_TAG" "$REPO_ROOT"
docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  -v "$REPO_ROOT":/workspace \
  "$IMAGE_TAG" \
  /bin/bash -lc '
    set -euo pipefail
    cat > /workspace/android/local.properties <<EOF
sdk.dir=/opt/android-sdk
flutter.sdk=/opt/flutter
EOF
    cd /workspace
    flutter pub get
  '

echo "Updated pubspec.lock using the pinned Docker toolchain."
