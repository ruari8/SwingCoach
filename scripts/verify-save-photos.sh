#!/bin/bash
set -euo pipefail

# Verify Save to Photos with real exports and PhotoKit on an owned Simulator.
# Only camera input and detector windows are substituted in a scratch copy.
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/save-photos/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-save-photos.XXXXXX")
device=""
cleanup() {
    local status=$?
    local removed=true
    trap - EXIT
    if [[ -n "$device" ]]; then
        xcrun simctl terminate "$device" Pear.ai.SwingCoach >/dev/null 2>&1 || true
        xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
        xcrun simctl delete "$device" >/dev/null 2>&1 || true
        if xcrun simctl list devices | grep -Fq "$device"; then removed=false; status=1; fi
    fi
    rm -rf "$scratch"
    echo "exit=$status owned_simulator=$device absent_after_delete=$removed scratch_removed=true" > "$artifacts/cleanup.txt"
    echo "Verification exit=$status. Evidence: $artifacts"
    exit "$status"
}
trap cleanup EXIT

mkdir -p "$scratch/repo/SwingCoachUITests"
ditto "$repo/SwingCoach" "$scratch/repo/SwingCoach"
ditto "$repo/SwingCoach.xcodeproj" "$scratch/repo/SwingCoach.xcodeproj"
ditto "$repo/SwingCoachTests" "$scratch/repo/SwingCoachTests"
cp "$repo/scripts/verification/SavePhotosUITests.swift" "$scratch/repo/SwingCoachUITests/"
ffmpeg -v error -f lavfi -i 'testsrc2=size=360x640:rate=30:duration=2' \
    -c:v libx264 -pix_fmt yuv420p "$scratch/repo/SwingCoach/storage-fixture.mp4"
python3 "$repo/scripts/verification/inject-save-photos-fixture.py" "$scratch/repo/SwingCoach/CaptureView.swift"

device=$(xcrun simctl create "SwingCoach Save Photos $(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
{
    echo "route=disposable Simulator; driver=XCUITest; device_readiness=not-needed"
    echo "simulator=$device; fixture=synthetic video and deterministic detector windows; real export, library, and PhotoKit"
    echo "hardware_recording=unverified; human_actions=none"
    echo "actions=OFF/ON persistence,Manual full and ranged Trim exports,Auto export/review,local playback after relaunch,local deletion,Photos row counts"
    xcrun simctl list devices | grep -F "$device"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/route.txt"
xcodebuild -project "$scratch/repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$artifacts/build.log" 2>&1
app="$scratch/DerivedData/Build/Products/Debug-iphonesimulator/SwingCoach.app"
xcrun simctl install "$device" "$app"
xcrun simctl privacy "$device" revoke photos Pear.ai.SwingCoach
xcrun simctl privacy "$device" revoke photos-add Pear.ai.SwingCoach
{
    echo "simulator=$device configuration=Debug"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist"
    xcrun simctl launch --terminate-running-process "$device" Pear.ai.SwingCoach
    xcrun simctl spawn "$device" launchctl print user/501 | grep 'Pear.ai.SwingCoach'
    tcc_db="${HOME}/Library/Developer/CoreSimulator/Devices/$device/data/Library/TCC/TCC.db"
    tcc_rows=$(sqlite3 -readonly "$tcc_db" "SELECT service || '=' || auth_value FROM access WHERE client = 'Pear.ai.SwingCoach' ORDER BY service;" 2>/dev/null || true)
    echo "authorization_raw=${tcc_rows:-notDetermined}"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/doctor.txt"
xcrun simctl io "$device" screenshot "$artifacts/launch.png"
photos_db="${HOME}/Library/Developer/CoreSimulator/Devices/$device/data/Media/PhotoData/Photos.sqlite"
for phase in off on; do
    if [[ "$phase" == on ]]; then
        xcrun simctl terminate "$device" Pear.ai.SwingCoach >/dev/null 2>&1 || true
        xcrun simctl privacy "$device" grant photos Pear.ai.SwingCoach
        xcrun simctl privacy "$device" grant photos-add Pear.ai.SwingCoach
        tests=(-only-testing:SwingCoachUITests/SavePhotosUITests/testOnCreatesPhotosCopiesForManualTrimAndAuto)
    else
        tests=(-only-testing:SwingCoachTests/ClipStorageTests -only-testing:SwingCoachUITests/SavePhotosUITests/testOffPersistsAndSavesManualTrimAndAutoLocally)
    fi
    test_status=0
    xcodebuild -project "$scratch/repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
        -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
        -parallel-testing-enabled NO -resultBundlePath "$artifacts/$phase.xcresult" \
        "${tests[@]}" CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/$phase-test.log" 2>&1 || test_status=$?
    xcrun xcresulttool get test-results summary --path "$artifacts/$phase.xcresult" > "$artifacts/$phase-test-summary.json"
    xcrun xcresulttool export attachments --path "$artifacts/$phase.xcresult" --output-path "$artifacts/screenshots/$phase" > /dev/null
    xcrun simctl io "$device" screenshot "$artifacts/$phase-final-simulator.png"
    [[ "$test_status" -eq 0 ]] || exit "$test_status"
    container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
    python3 "$repo/scripts/verification/check-save-photos.py" "$phase" "$container" "$photos_db" "$artifacts/$phase-test-summary.json" > "$artifacts/$phase-storage-proof.txt"
done
printf 'PASS: OFF and ON Manual/Trim/Auto exports, persistence, local review/deletion, and Photos counts\n'
