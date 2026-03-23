#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE_TAG="${SECLUSO_REPRO_IMAGE_TAG:-secluso-mobile-repro:local}"
DOCKER_PLATFORM="${SECLUSO_DOCKER_PLATFORM:-linux/amd64}"

if [[ -z "${SECLUSO_ANDROID_SIGNING_DIR:-}" ]]; then
  echo "SECLUSO_ANDROID_SIGNING_DIR must point to a directory containing key.properties and the keystore" >&2
  exit 1
fi

"$SCRIPT_DIR/build_with_docker.sh"

docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  -e SECLUSO_ANDROID_SIGNING_DIR=/signing \
  -v "$REPO_ROOT":/workspace \
  -v "${SECLUSO_ANDROID_SIGNING_DIR}":/signing:ro \
  "$IMAGE_TAG" \
  /workspace/tool/repro/sign_android_release.sh
