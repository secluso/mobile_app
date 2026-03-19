#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
android_dir="$project_dir/android"

# 1. build the app in design-controller mode
# 2. build the androidTest APK that drives screenshots
# 3. upload both to AWS Device Farm
# 4. run on a curated Android phone pool
# 5. pull the screenshots back down into a local folder
#
# tells us what does the exact same UI ook like across a bunch of real consumer phones without manually tapping through everything by hand
region="${AWS_REGION:-us-west-2}"
project_name="${SECLUSO_DEVICEFARM_PROJECT_NAME:-Secluso Design Lab}"
run_name="${SECLUSO_DEVICEFARM_RUN_NAME:-design-lab-$(date +%Y%m%d-%H%M%S)}"
android_package="${SECLUSO_DESIGN_ANDROID_PACKAGE:-com.secluso.mobile}"
command_file="/data/user/0/${android_package}/files/design_command.txt"
output_dir="${1:-$project_dir/design_captures/devicefarm/$run_name}"
app_apk="${SECLUSO_DEVICEFARM_APP_APK:-$project_dir/build/app/outputs/flutter-apk/app-debug.apk}"
test_apk="${SECLUSO_DEVICEFARM_TEST_APK:-$project_dir/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk}"
device_pool_arn="${SECLUSO_DEVICEFARM_DEVICE_POOL_ARN:-}"
project_arn="${SECLUSO_DEVICEFARM_PROJECT_ARN:-}"
max_devices="${SECLUSO_DEVICEFARM_MAX_DEVICES:-6}"
skip_build="${SECLUSO_DEVICEFARM_SKIP_BUILD:-0}"
# We try to get a realistic spread of popular Android consumer phones first, then gracefully fall back if a specific model is not currently in the farm or not available.
preferred_models_csv="${SECLUSO_DEVICEFARM_PREFERRED_MODELS:-Google Pixel 9,Samsung Galaxy S24,Samsung Galaxy S23,Google Pixel 8,Google Pixel 7,Motorola moto g power}"

mkdir -p "$output_dir"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd aws
require_cmd curl
require_cmd flutter
require_cmd python3

json_field() {
  local payload="$1"
  local expression="$2"
  # Tiny JSON helper so the shell script stays readable without a full jq dependency
  python3 -c '
import json
import sys

expr = sys.argv[1]
value = json.load(sys.stdin)
for part in expr.split('.'):
    if not part:
        continue
    if isinstance(value, list):
        value = value[int(part)]
    else:
        value = value.get(part)
print("" if value is None else value)
' "$expression" <<<"$payload"
}

resolve_project_arn() {
  if [[ -n "$project_arn" ]]; then
    echo "$project_arn"
    return
  fi

  # Reuse the project when it already exists so repeated runs do not spam the account with throwaway Device Farm projects.
  local projects_json
  projects_json="$(aws devicefarm list-projects --region "$region" --output json)"
  local existing
  existing="$(
    python3 -c '
import json
import sys

target = sys.argv[1]
projects = json.load(sys.stdin).get("projects", [])
for project in projects:
    if project.get("name") == target:
        print(project.get("arn", ""))
        break
' "$project_name" <<<"$projects_json"
  )"
  if [[ -n "$existing" ]]; then
    echo "$existing"
    return
  fi

  local created_json
  created_json="$(
    aws devicefarm create-project \
      --region "$region" \
      --name "$project_name" \
      --output json
  )"
  json_field "$created_json" "project.arn"
}

build_artifacts() {
  if [[ "$skip_build" == "1" ]]; then
    return
  fi

  # Build a debug APK on purpose. The design-controller entry path in the app is debug-only right now
  (
    cd "$project_dir"
    flutter build apk \
      --debug \
      --dart-define=SECLUSO_DESIGN_CONTROLLER=true \
      --dart-define="SECLUSO_DESIGN_COMMAND_FILE=$command_file"
  )

  # The instrumentation APK is what actually drives the screenshot loop on the farm. It launches the app, writes commands, and saves screenshots.
  (
    cd "$android_dir"
    ./gradlew app:assembleAndroidTest
  )
}

ensure_artifacts_exist() {
  [[ -f "$app_apk" ]] || {
    echo "App APK not found: $app_apk" >&2
    exit 1
  }
  [[ -f "$test_apk" ]] || {
    echo "Instrumentation APK not found: $test_apk" >&2
    exit 1
  }
}

select_devices_json() {
  local devices_json
  devices_json="$(aws devicefarm list-devices --region "$region" --output json)"
  #  We first try a preferred "real consumer phone" list in priority order, then fill any remaining slots
  # from the rest of the available Android phone fleet. 
  python3 -c '
import json
import sys

preferred = [item.strip().lower() for item in sys.argv[1].split(",") if item.strip()]
limit = int(sys.argv[2])

devices = json.load(sys.stdin).get("devices", [])
eligible = []
for device in devices:
    if device.get("platform") != "ANDROID":
        continue
    if device.get("formFactor") != "PHONE":
        continue
    if device.get("availability") not in {"AVAILABLE", "HIGHLY_AVAILABLE"}:
        continue
    eligible.append(device)

def haystack(device):
    fields = [
        device.get("manufacturer", ""),
        device.get("model", ""),
        device.get("name", ""),
        device.get("os", ""),
    ]
    return " ".join(fields).lower()

selected = []
seen = set()

for pref in preferred:
    for device in eligible:
        arn = device.get("arn")
        if not arn or arn in seen:
            continue
        if pref in haystack(device):
            selected.append(device)
            seen.add(arn)
            break
    if len(selected) >= limit:
        break

if len(selected) < limit:
    remaining = sorted(
        (device for device in eligible if device.get("arn") not in seen),
        key=lambda device: (
            device.get("manufacturer", ""),
            device.get("model", ""),
            device.get("os", ""),
        ),
    )
    for device in remaining:
        selected.append(device)
        if len(selected) >= limit:
            break

print(json.dumps(selected, indent=2))
' "$preferred_models_csv" "$max_devices" <<<"$devices_json"
}

create_device_pool() {
  if [[ -n "$device_pool_arn" ]]; then
    echo "$device_pool_arn"
    return
  fi

  # Device Farm pools want rule JSON
  local selected_devices_json="$1"
  local rules_file
  rules_file="$(mktemp)"

  python3 -c '
import json
import sys

devices = json.load(sys.stdin)
arns = [device["arn"] for device in devices if device.get("arn")]
if not arns:
    raise SystemExit("No eligible Android phone devices found in Device Farm.")

rules = [
    {
        "attribute": "ARN",
        "operator": "IN",
        "value": json.dumps(arns),
    }
]
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(rules, fh)
' "$rules_file" <<<"$selected_devices_json"

  local created_json
  created_json="$(
    aws devicefarm create-device-pool \
      --region "$region" \
      --project-arn "$project_arn" \
      --name "Secluso Design Phones $(date +%Y%m%d-%H%M%S)" \
      --description "Auto-generated Android phone pool for design lab screenshots." \
      --max-devices "$max_devices" \
      --rules "file://$rules_file" \
      --output json
  )"
  rm -f "$rules_file"
  json_field "$created_json" "devicePool.arn"
}

wait_for_upload() {
  local upload_arn="$1"
  local kind="$2"

  # Uploads become usable only after Device Farm finishes processing them
  while true; do
    local upload_json
    upload_json="$(aws devicefarm get-upload --region "$region" --arn "$upload_arn" --output json)"
    local status
    status="$(json_field "$upload_json" "upload.status")"
    case "$status" in
      SUCCEEDED)
        return
        ;;
      FAILED)
        echo "$kind upload failed." >&2
        echo "$upload_json" >&2
        exit 1
        ;;
    esac
    sleep 3
  done
}

create_upload() {
  local file_path="$1"
  local upload_type="$2"
  local content_type="$3"

  # Device Farm gives back a presigned URL; we upload the file there, then wait for Device Farm to finish ingesting/processing it before using the ARN.
  local upload_json
  upload_json="$(
    aws devicefarm create-upload \
      --region "$region" \
      --project-arn "$project_arn" \
      --name "$(basename "$file_path")" \
      --type "$upload_type" \
      --content-type "$content_type" \
      --output json
  )"

  local upload_arn upload_url
  upload_arn="$(json_field "$upload_json" "upload.arn")"
  upload_url="$(json_field "$upload_json" "upload.url")"

  curl --fail --silent --show-error -T "$file_path" "$upload_url" >/dev/null
  wait_for_upload "$upload_arn" "$(basename "$file_path")"
  echo "$upload_arn"
}

wait_for_run() {
  local run_arn="$1"

  # We only hard-stop on terminal infrastructure states here
  while true; do
    local run_json
    run_json="$(aws devicefarm get-run --region "$region" --arn "$run_arn" --output json)"
    local status result
    status="$(json_field "$run_json" "run.status")"
    result="$(json_field "$run_json" "run.result")"
    case "$status" in
      COMPLETED)
        return
        ;;
      ERRORED|STOPPED)
        echo "Device Farm run stopped with status: $status" >&2
        echo "$run_json" >&2
        exit 1
        ;;
    esac
    sleep 15
  done
}

download_test_screenshots() {
  local run_arn="$1"
  local jobs_json
  jobs_json="$(aws devicefarm list-jobs --region "$region" --arn "$run_arn" --output json)"

  # Screenshots usually show up as SCREENSHOT artifacts, but Device Farm can be consistent so we support others too
  python3 -c '
import json
import os
import re
import subprocess
import sys

output_dir = sys.argv[1]
region = sys.argv[2]
jobs = json.load(sys.stdin).get("jobs", [])

def sanitize(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("_") or "device"

def aws_json(*args):
    result = subprocess.run(
        ["aws", "devicefarm", *args, "--region", region, "--output", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)

for job in jobs:
    job_arn = job.get("arn")
    if not job_arn:
        continue
    job_dir = os.path.join(output_dir, sanitize(job.get("name", "job")))
    os.makedirs(job_dir, exist_ok=True)

    suites = aws_json("list-suites", "--arn", job_arn).get("suites", [])
    for suite in suites:
        suite_arn = suite.get("arn")
        if not suite_arn:
            continue
        tests = aws_json("list-tests", "--arn", suite_arn).get("tests", [])
        for test in tests:
            test_arn = test.get("arn")
            if not test_arn:
                continue
            artifacts = aws_json("list-artifacts", "--arn", test_arn, "--type", "SCREENSHOT").get("artifacts", [])
            if not artifacts:
                artifacts = [
                    artifact
                    for artifact in aws_json("list-artifacts", "--arn", test_arn, "--type", "FILE").get("artifacts", [])
                    if (artifact.get("extension") or "").lower() == "png"
                ]
            for index, artifact in enumerate(artifacts, start=1):
                url = artifact.get("url")
                if not url:
                    continue
                extension = artifact.get("extension") or "png"
                name = sanitize(artifact.get("name", f"screenshot_{index}"))
                out_path = os.path.join(job_dir, f"{index:02d}_{name}.{extension}")
                subprocess.run(
                    ["curl", "--fail", "--silent", "--show-error", url, "-o", out_path],
                    check=True,
                )
' "$output_dir" "$region" <<<"$jobs_json"
}

build_artifacts
ensure_artifacts_exist

project_arn="$(resolve_project_arn)"
selected_devices_json="$(select_devices_json)"
device_pool_arn="$(create_device_pool "$selected_devices_json")"

# Upload app APK first, then the instrumentation package that will control it.
app_upload_arn="$(
  create_upload \
    "$app_apk" \
    "ANDROID_APP" \
    "application/vnd.android.package-archive"
)"
test_upload_arn="$(
  create_upload \
    "$test_apk" \
    "INSTRUMENTATION_TEST_PACKAGE" \
    "application/vnd.android.package-archive"
)"

run_json="$(
  aws devicefarm schedule-run \
    --region "$region" \
    --project-arn "$project_arn" \
    --app-arn "$app_upload_arn" \
    --device-pool-arn "$device_pool_arn" \
    --name "$run_name" \
    --test "type=INSTRUMENTATION,testPackageArn=$test_upload_arn" \
    --output json
)"
run_arn="$(json_field "$run_json" "run.arn")"

wait_for_run "$run_arn"
download_test_screenshots "$run_arn"

# Write a small machine-readable summary 
python3 -c '
import json
import sys

summary_path = sys.argv[1]
project_arn = sys.argv[2]
device_pool_arn = sys.argv[3]
run_arn = sys.argv[4]
devices = json.load(sys.stdin)

summary = {
    "projectArn": project_arn,
    "devicePoolArn": device_pool_arn,
    "runArn": run_arn,
    "devices": [
        {
            "name": device.get("name"),
            "manufacturer": device.get("manufacturer"),
            "model": device.get("model"),
            "os": device.get("os"),
            "arn": device.get("arn"),
        }
        for device in devices
    ],
}

with open(summary_path, "w", encoding="utf-8") as fh:
    json.dump(summary, fh, indent=2)
' "$output_dir/run_summary.json" "$project_arn" "$device_pool_arn" "$run_arn" <<<"$selected_devices_json"

echo "$output_dir"
