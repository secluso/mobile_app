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

if [[ -z "${SOURCE_DATE_EPOCH:-}" ]] && git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
  export SOURCE_DATE_EPOCH
  SOURCE_DATE_EPOCH="$(git -C "$REPO_ROOT" log -1 --format=%ct)"
fi

docker build --platform "$DOCKER_PLATFORM" -f "$SCRIPT_DIR/Dockerfile" -t "$IMAGE_TAG" "$REPO_ROOT"
docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  -e SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1704067200}" \
  -v "$REPO_ROOT":/workspace \
  "$IMAGE_TAG" \
  /workspace/tool/repro/build_unsigned_android_release.sh
