#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_ID="${SECLUSO_FDROID_APP_ID:-com.secluso.mobile}"
METADATA_SOURCE="${SECLUSO_FDROID_METADATA_SOURCE:-$REPO_ROOT/fdroid/$APP_ID.yml}"
FDROIDSERVER_DIR="${SECLUSO_FDROIDSERVER_DIR:-$REPO_ROOT/.secluso-repro-cache/fdroidserver}"
FDROIDSERVER_REF="${SECLUSO_FDROIDSERVER_REF:-master}"
FDROIDSERVER_REPO_URL="${SECLUSO_FDROIDSERVER_REPO_URL:-https://gitlab.com/fdroid/fdroidserver.git}"
FDROID_IMAGE="${SECLUSO_FDROID_BUILDSERVER_IMAGE:-registry.gitlab.com/fdroid/fdroidserver:buildserver-trixie}"
DOCKER_PLATFORM="${SECLUSO_DOCKER_PLATFORM:-linux/amd64}"
KEEP_WORK_ROOT="${KEEP_WORK_ROOT:-0}"
REQUIRE_VERIFY="${SECLUSO_FDROID_REQUIRE_VERIFY:-0}"
SRCLIBS_SOURCE_DIR="${SECLUSO_FDROID_SRCLIBS_DIR:-$REPO_ROOT/../fdroiddata/srclibs}"
OUTPUT_DIR="${SECLUSO_FDROID_OUTPUT_DIR:-$REPO_ROOT/build/reproducible/fdroid}"
WORK_ROOT="${SECLUSO_FDROID_BUILD_WORKDIR:-$(mktemp -d "${TMPDIR:-/tmp}/secluso-fdroid-build.XXXXXX")}"
METADATA_SOURCE_REL="${METADATA_SOURCE#$REPO_ROOT/}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

if [[ ! -f "$METADATA_SOURCE" ]]; then
  echo "F-Droid metadata source not found at $METADATA_SOURCE" >&2
  exit 1
fi

metadata_version_codes() {
  sed -n -E 's/^    versionCode: ([0-9]+)$/\1/p' "$METADATA_SOURCE"
}

abi_name_from_version_code() {
  case "${1: -1}" in
    1)
      printf '%s\n' "armeabi-v7a"
      ;;
    2)
      printf '%s\n' "arm64-v8a"
      ;;
    3)
      printf '%s\n' "x86_64"
      ;;
    *)
      return 1
      ;;
  esac
}

DEFAULT_VERSION_CODE="$(metadata_version_codes | head -n 1)"
VERSION_CODE="${SECLUSO_FDROID_VERSION_CODE:-$DEFAULT_VERSION_CODE}"
if [[ -z "$VERSION_CODE" ]]; then
  echo "Could not determine versionCode from $METADATA_SOURCE" >&2
  exit 1
fi
if ! metadata_version_codes | grep -qx "$VERSION_CODE"; then
  echo "versionCode $VERSION_CODE is not present in $METADATA_SOURCE" >&2
  exit 1
fi
ABI_NAME="$(abi_name_from_version_code "$VERSION_CODE" || true)"
if [[ -n "$ABI_NAME" ]]; then
  DEFAULT_OUTPUT_APK="$OUTPUT_DIR/app-$ABI_NAME-release-unsigned.apk"
  DEFAULT_REFERENCE_APK="$OUTPUT_DIR/reference-$ABI_NAME-release-signed.apk"
  DEFAULT_LOG_FILE="$OUTPUT_DIR/fdroid-build-$ABI_NAME.log"
else
  DEFAULT_OUTPUT_APK="$OUTPUT_DIR/app-release-unsigned.apk"
  DEFAULT_REFERENCE_APK="$OUTPUT_DIR/reference-release-signed.apk"
  DEFAULT_LOG_FILE="$OUTPUT_DIR/fdroid-build.log"
fi
OUTPUT_APK="${SECLUSO_FDROID_OUTPUT_APK:-$DEFAULT_OUTPUT_APK}"
REFERENCE_APK="${SECLUSO_FDROID_REFERENCE_APK:-$DEFAULT_REFERENCE_APK}"
LOG_FILE="${SECLUSO_FDROID_OUTPUT_LOG:-$DEFAULT_LOG_FILE}"
BUILD_SPEC="${APP_ID}:${VERSION_CODE}"

metadata_source_epoch() {
  local epoch

  epoch="$(git -C "$REPO_ROOT" log -n 1 --pretty=%ct -- "$METADATA_SOURCE_REL" 2>/dev/null || true)"
  if [[ -n "$epoch" ]]; then
    printf '%s\n' "$epoch"
    return 0
  fi

  if stat -f %m "$METADATA_SOURCE" >/dev/null 2>&1; then
    stat -f %m "$METADATA_SOURCE"
  else
    stat -c %Y "$METADATA_SOURCE"
  fi
}

bootstrap_fdroidserver() {
  if ! command -v git >/dev/null 2>&1; then
    echo "git is required to bootstrap fdroidserver" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$FDROIDSERVER_DIR")"
  if [[ -d "$FDROIDSERVER_DIR/.git" ]]; then
    git -C "$FDROIDSERVER_DIR" fetch --depth=1 origin "$FDROIDSERVER_REF"
    git -C "$FDROIDSERVER_DIR" reset --hard FETCH_HEAD
    git -C "$FDROIDSERVER_DIR" clean -dffx
    return 0
  fi

  rm -rf "$FDROIDSERVER_DIR"
  git clone --depth=1 --branch "$FDROIDSERVER_REF" "$FDROIDSERVER_REPO_URL" "$FDROIDSERVER_DIR"
}

cleanup() {
  if [[ "$KEEP_WORK_ROOT" != "1" ]]; then
    rm -rf "$WORK_ROOT"
  else
    printf 'Preserving F-Droid work directory: %s\n' "$WORK_ROOT"
  fi
}
trap cleanup EXIT

bootstrap_fdroidserver

mkdir -p "$WORK_ROOT/config" "$WORK_ROOT/metadata" "$WORK_ROOT/srclibs" "$OUTPUT_DIR"
cp "$METADATA_SOURCE" "$WORK_ROOT/metadata/$APP_ID.yml"

cat > "$WORK_ROOT/config.yml" <<'EOF'
repo_url: https://example.com/fdroid/repo
repo_name: Secluso Local F-Droid Repro Test Repo
sdk_path: /opt/android-sdk
serverwebroot: /tmp
nonstandardwebroot: true
keep_when_not_allowed: true
make_current_version_link: false
refresh_scanner: true
EOF
chmod 600 "$WORK_ROOT/config.yml"

cat > "$WORK_ROOT/config/categories.yml" <<'EOF'
Internet:
  name: Internet
Security:
  name: Security
EOF

if [[ -d "$SRCLIBS_SOURCE_DIR" ]]; then
  find "$SRCLIBS_SOURCE_DIR" -maxdepth 1 -name '*.yml' -exec cp {} "$WORK_ROOT/srclibs/" \;
fi

if [[ ! -f "$WORK_ROOT/srclibs/flutter.yml" ]]; then
  cat > "$WORK_ROOT/srclibs/flutter.yml" <<'EOF'
RepoType: git
Repo: https://github.com/flutter/flutter.git
EOF
fi

METADATA_EPOCH="$(metadata_source_epoch)"
git -C "$WORK_ROOT" init -q
git -C "$WORK_ROOT" config user.name "Secluso Repro Bot"
git -C "$WORK_ROOT" config user.email "repro@secluso.invalid"
git -C "$WORK_ROOT" add config metadata srclibs
GIT_AUTHOR_DATE="@$METADATA_EPOCH" \
GIT_COMMITTER_DATE="@$METADATA_EPOCH" \
  git -C "$WORK_ROOT" commit -q -m "Seed F-Droid repro workspace"

read -r -d '' CONTAINER_COMMAND <<EOF || true
set -euo pipefail

. /etc/profile

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
# Match the mutable Android toolchain prep from fdroiddata GitLab CI.
sdkmanager "platform-tools" "build-tools;31.0.0"
DEBIAN_FRONTEND=noninteractive apt-get install -y sudo openjdk-21-jdk-headless
update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java

chown vagrant:vagrant /home/vagrant
find /home/vagrant -mindepth 1 -maxdepth 1 ! -name fdroidserver -exec chown -R vagrant:vagrant {} +

if [[ -d /home/vagrant/gradlew-fdroid/.git ]]; then
  git -C /home/vagrant/gradlew-fdroid pull
fi

sudo --preserve-env --user vagrant \
  env PYTHONUNBUFFERED=true \
  env HOME=/home/vagrant \
  bash -c '
    set -euo pipefail
    . /etc/profile
    export PATH="/home/vagrant/fdroidserver:$PATH"
    export PYTHONPATH="/home/vagrant/fdroidserver:/home/vagrant/fdroidserver/examples"
    cd /home/vagrant
    fdroid readmeta
    fdroid rewritemeta $APP_ID
    fdroid lint $APP_ID
    fdroid fetchsrclibs --verbose $BUILD_SPEC
    fdroid build --verbose --test --refresh-scanner --on-server --no-tarball $BUILD_SPEC
  '
EOF

set +e
docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  --entrypoint /bin/bash \
  -v "$WORK_ROOT":/home/vagrant \
  -v "$FDROIDSERVER_DIR":/home/vagrant/fdroidserver:ro \
  "$FDROID_IMAGE" \
  -lc "$CONTAINER_COMMAND" 2>&1 | tee "$LOG_FILE"
BUILD_STATUS="${PIPESTATUS[0]}"
set -e

UNSIGNED_SOURCE="$WORK_ROOT/tmp/${APP_ID}_${VERSION_CODE}.apk"
REFERENCE_SOURCE="$WORK_ROOT/tmp/binaries/${APP_ID}_${VERSION_CODE}.binary.apk"

if [[ ! -f "$UNSIGNED_SOURCE" ]]; then
  echo "Canonical F-Droid unsigned APK was not produced. See $LOG_FILE" >&2
  exit "${BUILD_STATUS:-1}"
fi

cp "$UNSIGNED_SOURCE" "$OUTPUT_APK"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUTPUT_APK" | tee "$OUTPUT_APK.sha256"
else
  shasum -a 256 "$OUTPUT_APK" | tee "$OUTPUT_APK.sha256"
fi

if [[ -f "$REFERENCE_SOURCE" ]]; then
  cp "$REFERENCE_SOURCE" "$REFERENCE_APK"
fi

printf '\n==> Canonical F-Droid unsigned APK ready at %s\n' "$OUTPUT_APK"
printf '==> F-Droid build log saved at %s\n' "$LOG_FILE"

if [[ -f "$REFERENCE_SOURCE" ]]; then
  printf '==> Current reference signed APK copied to %s\n' "$REFERENCE_APK"
fi

if [[ "$BUILD_STATUS" -ne 0 ]]; then
  cat >&2 <<EOF
F-Droid produced the unsigned APK, but the full verification run did not pass.
This usually means the published signed APK in Binaries does not yet match this
canonical unsigned artifact.

If you want this script to fail in that case, set:
  SECLUSO_FDROID_REQUIRE_VERIFY=1
EOF
  if [[ "$REQUIRE_VERIFY" == "1" ]]; then
    exit "$BUILD_STATUS"
  fi
fi
