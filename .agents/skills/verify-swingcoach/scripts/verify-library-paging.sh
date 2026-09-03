#!/bin/bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skill_dir=$(cd "$script_dir/.." && pwd)
repo_root=$(git -C "$skill_dir" rev-parse --show-toplevel)
bundle_id="Pear.ai.SwingCoach"
device_type="${SWINGCOACH_VERIFY_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17}"
runtime="${SWINGCOACH_VERIFY_RUNTIME:-}"
run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
reference_dir="$repo_root/SwingCoach/ReferenceSwings"
reference_files=(DaB3eJ3gAcv_1.mp4 DaBMIbhpel9_1.mp4 DaD04inv5-Z_1.mp4)

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [artifact-directory]" >&2
    exit 64
fi

for reference_file in "${reference_files[@]}"; do
    if [[ ! -f "$reference_dir/$reference_file" ]]; then
        echo "Missing ignored local fixture: $reference_dir/$reference_file" >&2
        echo "See $reference_dir/README.md for setup." >&2
        exit 66
    fi
done

artifact_dir="${1:-$repo_root/.verification-artifacts/library-paging/$run_id}"
if [[ "$artifact_dir" != /* ]]; then
    artifact_dir="$repo_root/$artifact_dir"
fi
mkdir -p "$artifact_dir"

scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-verify.XXXXXX")
scratch_repo="$scratch_dir/repo"
derived_data="$scratch_dir/DerivedData"
simulator_udid=""
cleanup_started=0

cleanup() {
    local command_status=$?
    if [[ $cleanup_started -eq 1 ]]; then
        return
    fi
    cleanup_started=1
    trap - EXIT INT TERM

    {
        echo "command_status=$command_status"
        echo "simulator_udid=${simulator_udid:-not-created}"
        if [[ -n "$simulator_udid" ]]; then
            xcrun simctl terminate "$simulator_udid" "$bundle_id" >/dev/null 2>&1 || true
            xcrun simctl shutdown "$simulator_udid" >/dev/null 2>&1 || true
            xcrun simctl delete "$simulator_udid" >/dev/null 2>&1 || true
            if xcrun simctl list devices | grep -Fq "$simulator_udid"; then
                echo "simulator_absent_after_delete=false"
            else
                echo "simulator_absent_after_delete=true"
            fi
        else
            echo "simulator_absent_after_delete=not-created"
        fi
        echo "scratch_removed=$scratch_dir"
        echo "proof_preserved=$artifact_dir"
    } > "$artifact_dir/cleanup.txt"

    if [[ "$scratch_dir" == "${TMPDIR:-/tmp}"/swingcoach-verify.* ]]; then
        rm -rf "$scratch_dir"
    else
        echo "Refusing to remove unexpected scratch path: $scratch_dir" >&2
        command_status=70
    fi

    if [[ $command_status -eq 0 ]]; then
        echo "PASS: library reference paging"
    else
        echo "FAIL: library reference paging (exit $command_status)" >&2
    fi
    echo "Artifacts: $artifact_dir"
    exit "$command_status"
}
trap cleanup EXIT INT TERM

mkdir -p "$scratch_repo/SwingCoachUITests"
ditto "$repo_root/SwingCoach" "$scratch_repo/SwingCoach"
ditto "$repo_root/SwingCoach.xcodeproj" "$scratch_repo/SwingCoach.xcodeproj"
ditto "$repo_root/SwingCoachUITests" "$scratch_repo/SwingCoachUITests"
cp "$skill_dir/assets/SwingCoachVerificationUITests.swift" "$scratch_repo/SwingCoachUITests/"

if [[ -n "$runtime" ]]; then
    simulator_udid=$(xcrun simctl create "SwingCoach Verify $run_id" "$device_type" "$runtime")
else
    simulator_udid=$(xcrun simctl create "SwingCoach Verify $run_id" "$device_type")
fi
echo "$simulator_udid" > "$artifact_dir/simulator-udid.txt"
xcrun simctl boot "$simulator_udid"
xcrun simctl bootstatus "$simulator_udid" -b

git_revision=$(git -C "$repo_root" rev-parse HEAD)
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    git_dirty=true
else
    git_dirty=false
fi
simulator_os=$(xcrun simctl getenv "$simulator_udid" SIMULATOR_RUNTIME_VERSION 2>/dev/null || echo "unknown")

{
    echo "route=simulator"
    echo "driver=XCUITest"
    echo "device_readiness=not-needed"
    echo "simulator_udid=$simulator_udid"
    echo "simulator_os=$simulator_os"
    echo "git_revision=$git_revision"
    echo "git_dirty=$git_dirty"
    echo "fixture=Local Reference swing 1"
    echo "permission_state=recorded-in-doctor.txt"
    echo "automated_actions=launch,select Library,open Reference swing 1,swipe review page,read swing position"
    echo "human_actions=none"
    echo "started_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$artifact_dir/route.txt"

xcodebuild \
    -project "$scratch_repo/SwingCoach.xcodeproj" \
    -scheme SwingCoach \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator_udid" \
    -derivedDataPath "$derived_data" \
    build 2>&1 | tee "$artifact_dir/build.log"

app_path="$derived_data/Build/Products/Debug-iphonesimulator/SwingCoach.app"
if [[ ! -d "$app_path" ]]; then
    echo "Built app not found at $app_path" >&2
    exit 66
fi

xcrun simctl install "$simulator_udid" "$app_path"
launch_output=$(xcrun simctl launch --terminate-running-process "$simulator_udid" "$bundle_id")
echo "$launch_output" > "$artifact_dir/launch.txt"

installed_app=$(xcrun simctl get_app_container "$simulator_udid" "$bundle_id" app)
installed_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Info.plist")
installed_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$installed_app/Info.plist")
simulator_line=$(xcrun simctl list devices | grep -F "$simulator_udid")
launch_services=""
for _ in 1 2 3 4 5; do
    launch_services=$(xcrun simctl spawn "$simulator_udid" launchctl print user/501)
    if grep -Fq "$bundle_id" <<< "$launch_services"; then
        break
    fi
    sleep 1
done
if ! grep -Fq "$bundle_id" <<< "$launch_services"; then
    echo "Doctor could not find the running app process" >&2
    exit 69
fi
xcrun simctl io "$simulator_udid" screenshot "$artifact_dir/launch.png"

tcc_db="${HOME}/Library/Developer/CoreSimulator/Devices/$simulator_udid/data/Library/TCC/TCC.db"
if [[ -f "$tcc_db" ]]; then
    tcc_rows=$(sqlite3 -readonly "$tcc_db" "SELECT service || '=' || auth_value FROM access WHERE client = '$bundle_id' ORDER BY service;" 2>/dev/null || true)
else
    tcc_rows=""
fi
if [[ -z "$tcc_rows" ]]; then
    tcc_rows="notDetermined"
fi

{
    echo "simulator_udid=$simulator_udid"
    echo "simulator=$simulator_line"
    echo "bundle_id=$installed_bundle"
    echo "bundle_version=$installed_version"
    echo "configuration=Debug"
    echo "app_container=$installed_app"
    echo "launch=$launch_output"
    echo "git_revision=$git_revision"
    echo "git_dirty=$git_dirty"
    echo "photos_authorization_raw=$tcc_rows"
} > "$artifact_dir/doctor.txt"

if [[ "$installed_bundle" != "$bundle_id" ]]; then
    echo "Doctor found bundle $installed_bundle, expected $bundle_id" >&2
    exit 69
fi
if [[ "$simulator_line" != *"(Booted)"* ]]; then
    echo "Doctor found simulator is not booted: $simulator_line" >&2
    exit 69
fi

result_bundle="$artifact_dir/library-reference-paging.xcresult"
xcodebuild \
    -project "$scratch_repo/SwingCoach.xcodeproj" \
    -scheme SwingCoach \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator_udid" \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled NO \
    -only-testing:SwingCoachUITests/SwingCoachVerificationUITests/testLibraryReferencePagingFromTab \
    test 2>&1 | tee "$artifact_dir/test.log"

xcrun xcresulttool get test-results summary --path "$result_bundle" > "$artifact_dir/test-summary.json"
mkdir -p "$artifact_dir/screenshots"
xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$artifact_dir/screenshots" > "$artifact_dir/attachments-export.txt"
xcrun simctl io "$simulator_udid" screenshot "$artifact_dir/final-simulator.png"
