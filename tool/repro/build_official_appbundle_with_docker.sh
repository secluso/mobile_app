#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKER_PLATFORM="${SECLUSO_DOCKER_PLATFORM:-linux/amd64}"

dockerfile_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$SCRIPT_DIR/Dockerfile" | awk '{print substr($1, 1, 12)}'
  else
    shasum -a 256 "$SCRIPT_DIR/Dockerfile" | awk '{print substr($1, 1, 12)}'
  fi
}

DEFAULT_IMAGE_TAG="secluso-mobile-repro:$(dockerfile_hash)"
IMAGE_TAG="${SECLUSO_REPRO_IMAGE_TAG:-$DEFAULT_IMAGE_TAG}"

if [[ -z "${SECLUSO_ANDROID_SIGNING_DIR:-}" ]]; then
  echo "SECLUSO_ANDROID_SIGNING_DIR must point to a directory containing key.properties and the keystore" >&2
  exit 1
fi

"$SCRIPT_DIR/build_aab_with_docker.sh"

docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  -e SECLUSO_ANDROID_SIGNING_DIR=/signing \
  -v "$REPO_ROOT":/workspace \
  -v "${SECLUSO_ANDROID_SIGNING_DIR}":/signing:ro \
  "$IMAGE_TAG" \
  /workspace/tool/repro/sign_android_appbundle.sh

if [[ -f "$REPO_ROOT/build/reproducible/app-release-signed.aab.sha256" ]]; then
  tmp_sha="$(mktemp "${TMPDIR:-/tmp}/secluso-signed-aab-sha.XXXXXX")"
  sed "s|/workspace|$REPO_ROOT|g" \
    "$REPO_ROOT/build/reproducible/app-release-signed.aab.sha256" > "$tmp_sha"
  mv "$tmp_sha" "$REPO_ROOT/build/reproducible/app-release-signed.aab.sha256"
fi

printf '\n==> Host signed artifact ready at %s\n' "$REPO_ROOT/build/reproducible/app-release-signed.aab"
