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
UNSIGNED_APK="${SECLUSO_FDROID_OUTPUT_APK:-$REPO_ROOT/build/reproducible/fdroid/app-release-unsigned.apk}"
SIGNED_APK="${SECLUSO_FDROID_SIGNED_APK:-$REPO_ROOT/build/reproducible/fdroid/app-release-signed.apk}"

if [[ -z "${SECLUSO_ANDROID_SIGNING_DIR:-}" ]]; then
  echo "SECLUSO_ANDROID_SIGNING_DIR must point to a directory containing key.properties and the keystore" >&2
  exit 1
fi

"$SCRIPT_DIR/build_fdroid_unsigned_with_buildserver.sh"

if [[ "${SECLUSO_REPRO_FORCE_IMAGE_BUILD:-0}" == "1" ]] || ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  docker build --platform "$DOCKER_PLATFORM" -f "$SCRIPT_DIR/Dockerfile" -t "$IMAGE_TAG" "$REPO_ROOT"
fi

docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  -e SECLUSO_ANDROID_SIGNING_DIR=/signing \
  -e UNSIGNED_APK="/workspace${UNSIGNED_APK#$REPO_ROOT}" \
  -e SIGNED_APK="/workspace${SIGNED_APK#$REPO_ROOT}" \
  -v "$REPO_ROOT":/workspace \
  -v "${SECLUSO_ANDROID_SIGNING_DIR}":/signing:ro \
  "$IMAGE_TAG" \
  /workspace/tool/repro/sign_android_release.sh

if [[ -f "$SIGNED_APK.sha256" ]]; then
  tmp_sha="$(mktemp "${TMPDIR:-/tmp}/secluso-fdroid-signed-apk-sha.XXXXXX")"
  sed "s|/workspace|$REPO_ROOT|g" "$SIGNED_APK.sha256" > "$tmp_sha"
  mv "$tmp_sha" "$SIGNED_APK.sha256"
fi

printf '\n==> Canonical F-Droid signed artifact ready at %s\n' "$SIGNED_APK"
