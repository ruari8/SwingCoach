#!/bin/bash
set -euo pipefail

# Substitute only camera file output in a scratch copy. The record controls,
# recording delegate, Trim presentation, Cancel, and cleanup are production code.
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/manual-trim-cancel/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-manual-cancel.XXXXXX")
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
cp "$repo/scripts/verification/ManualTrimCancelUITests.swift" "$scratch/repo/SwingCoachUITests/"
ffmpeg -v error -f lavfi -i 'testsrc2=size=360x640:rate=30:duration=2' \
    -c:v libx264 -pix_fmt yuv420p "$scratch/repo/SwingCoach/manual-cancel-fixture.mp4"
python3 - "$scratch/repo/SwingCoach/CaptureView.swift" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
start = source.index('    func startRecording() {')
end = source.index('    func startAutoCapture() {', start)
source = source[:start] + '''    func startRecording() {
        recordedMode = captureMode
    }

    func stopRecording() {
        let fixture = Bundle.main.url(forResource: "manual-cancel-fixture", withExtension: "mp4")!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manual-cancel-\\(UUID().uuidString).mp4")
        try! FileManager.default.copyItem(at: fixture, to: url)
        fileOutput(movieOutput, didFinishRecordingTo: url, from: [], error: nil)
    }

''' + source[end:]
path.write_text(source)
PY

device=$(xcrun simctl create "SwingCoach Manual Cancel $(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
{
    echo "route=disposable Simulator; driver=XCUITest; device_readiness=not-needed"
    echo "simulator=$device; fixture=synthetic 2-second video replacing camera file output"
    echo "hardware_recording=unverified; human_actions=none"
    echo "actions=Auto to Manual,record,stop,Trim,Cancel,repeat,Library to Capture"
    xcrun simctl list devices | grep -F "$device"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/route.txt"
xcodebuild -project "$scratch/repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$artifacts/build.log" 2>&1
app="$scratch/DerivedData/Build/Products/Debug-iphonesimulator/SwingCoach.app"
xcrun simctl install "$device" "$app"
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
test_status=0
xcodebuild -project "$scratch/repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    -parallel-testing-enabled NO -resultBundlePath "$artifacts/manual-cancel.xcresult" \
    -only-testing:SwingCoachUITests/ManualTrimCancelUITests \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/test.log" 2>&1 || test_status=$?
xcrun xcresulttool get test-results summary --path "$artifacts/manual-cancel.xcresult" > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$artifacts/manual-cancel.xcresult" --output-path "$artifacts/screenshots" > /dev/null
xcrun simctl io "$device" screenshot "$artifacts/final-simulator.png"
[[ "$test_status" -eq 0 ]] || exit "$test_status"
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
python3 - "$container" "$artifacts/test-summary.json" <<'PY'
from pathlib import Path
import json, sys
root = Path(sys.argv[1])
summary = json.loads(Path(sys.argv[2]).read_text())
assert summary['passedTests'] == 1 and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
assert not list((root / 'tmp').glob('manual-cancel-*.mp4')), 'Cancelled recording was not removed'
print('PASS: Cancel returns to Manual twice and removes temporary recordings')
PY
