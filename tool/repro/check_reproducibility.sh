#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE_TAG="${SECLUSO_REPRO_IMAGE_TAG:-secluso-mobile-repro:local}"
DOCKER_PLATFORM="${SECLUSO_DOCKER_PLATFORM:-linux/amd64}"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/secluso-mobile-repro.XXXXXX")"
KEEP_WORK_ROOT="${KEEP_WORK_ROOT:-0}"
SOURCE_DATE_EPOCH_VALUE="${SOURCE_DATE_EPOCH:-}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

cleanup() {
  if [[ "$KEEP_WORK_ROOT" != "1" ]]; then
    rm -rf "$WORK_ROOT"
  else
    echo "Preserving work directory: $WORK_ROOT"
  fi
}
trap cleanup EXIT

if [[ -z "$SOURCE_DATE_EPOCH_VALUE" ]] && git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
  SOURCE_DATE_EPOCH_VALUE="$(git -C "$REPO_ROOT" log -1 --format=%ct)"
fi
if [[ -z "$SOURCE_DATE_EPOCH_VALUE" ]]; then
  SOURCE_DATE_EPOCH_VALUE="1704067200"
fi

copy_workspace() {
  local destination="$1"
  mkdir -p "$destination"
  rsync -a \
    --exclude '.dart_tool' \
    --exclude '.git' \
    --exclude 'android/local.properties' \
    --exclude 'build' \
    --exclude 'ios/Pods' \
    --exclude 'rust/target' \
    "$REPO_ROOT/" "$destination/"
}

run_build() {
  local workspace="$1"
  docker run --rm \
    --platform "$DOCKER_PLATFORM" \
    -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH_VALUE" \
    -v "$workspace":/workspace \
    "$IMAGE_TAG" \
    /workspace/tool/repro/build_unsigned_android_release.sh
}

BUILD_ONE="$WORK_ROOT/build-one"
BUILD_TWO="$WORK_ROOT/build-two"

copy_workspace "$BUILD_ONE"
copy_workspace "$BUILD_TWO"

docker build --platform "$DOCKER_PLATFORM" -f "$SCRIPT_DIR/Dockerfile" -t "$IMAGE_TAG" "$REPO_ROOT"

run_build "$BUILD_ONE"
run_build "$BUILD_TWO"

FIRST_APK="$BUILD_ONE/build/reproducible/app-release-unsigned.apk"
SECOND_APK="$BUILD_TWO/build/reproducible/app-release-unsigned.apk"

python3 "$REPO_ROOT/tool/repro/apkdiff.py" "$FIRST_APK" "$SECOND_APK"
echo "First build sha256:"
cat "$FIRST_APK.sha256"
echo "Second build sha256:"
cat "$SECOND_APK.sha256"
