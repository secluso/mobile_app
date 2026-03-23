#!/usr/bin/env bash

set -euo pipefail

OUTPUT_DIR="${1:-/tmp/secluso-signing}"
KEYSTORE_NAME="${SECLUSO_TEST_KEYSTORE_NAME:-test-release.jks}"
KEY_ALIAS="${SECLUSO_TEST_KEY_ALIAS:-secluso-test}"
STORE_PASSWORD="${SECLUSO_TEST_STORE_PASSWORD:-secluso-test-store-pass}"
KEY_PASSWORD="${SECLUSO_TEST_KEY_PASSWORD:-secluso-test-key-pass}"
VALIDITY_DAYS="${SECLUSO_TEST_KEY_VALIDITY_DAYS:-3650}"
DISTINGUISHED_NAME="${SECLUSO_TEST_KEY_DNAME:-CN=Secluso Test,O=Secluso,OU=Testing,L=Test,ST=Test,C=US}"

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool is required" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

KEYSTORE_PATH="$OUTPUT_DIR/$KEYSTORE_NAME"
KEY_PROPERTIES_PATH="$OUTPUT_DIR/key.properties"

if [[ -f "$KEYSTORE_PATH" ]]; then
  echo "Refusing to overwrite existing keystore: $KEYSTORE_PATH" >&2
  exit 1
fi

keytool -genkeypair \
  -keystore "$KEYSTORE_PATH" \
  -storetype JKS \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity "$VALIDITY_DAYS" \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "$DISTINGUISHED_NAME" \
  >/dev/null

cat > "$KEY_PROPERTIES_PATH" <<EOF
storeFile=$KEYSTORE_NAME
storePassword=$STORE_PASSWORD
keyAlias=$KEY_ALIAS
keyPassword=$KEY_PASSWORD
EOF

cat <<EOF
Created test-only Android signing material:
  Directory: $OUTPUT_DIR
  Keystore:  $KEYSTORE_PATH
  Config:    $KEY_PROPERTIES_PATH

Use it like this:
  SECLUSO_ANDROID_SIGNING_DIR=$OUTPUT_DIR tool/repro/build_official_release_with_docker.sh

This keystore is for local testing only. Do not use it for production releases.
EOF
