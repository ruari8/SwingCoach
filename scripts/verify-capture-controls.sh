#!/bin/bash
set -euo pipefail

# Verify production capture controls, settings persistence, and shared review.
# Only camera/Photos outputs and detector snapshots are substituted in a scratch copy.
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/capture-controls/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-capture-controls.XXXXXX")
device=""
suite="${2:-controls}"
case "$suite" in
    controls)
        test_selectors=(-only-testing:SwingCoachUITests/ManualTrimCancelUITests -only-testing:SwingCoachUITests/CaptureControlsUITests)
        expected_tests=6
        ;;
    annotations)
        test_selectors=(-only-testing:SwingCoachUITests/AutoReviewAnnotationUITests -only-testing:SwingCoachUITests/CaptureControlsUITests/testSavedReviewStillPlaysPagesAndDeletes)
        expected_tests=2
        ;;
    *) echo "Unknown verification suite: $suite" >&2; exit 2 ;;
esac
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
cp "$repo/scripts/verification/ManualTrimCancelUITests.swift" "$repo/scripts/verification/CaptureControlsUITests.swift" "$repo/scripts/verification/AutoReviewAnnotationUITests.swift" "$scratch/repo/SwingCoachUITests/"
ffmpeg -v error -f lavfi -i 'testsrc2=size=360x640:rate=30:duration=2' \
    -c:v libx264 -pix_fmt yuv420p "$scratch/repo/SwingCoach/manual-cancel-fixture.mp4"
if [[ "$suite" == annotations ]]; then
    # These fixtures exercise saved-clip identity without private range footage.
    for name in DaBMIbhpel9_1 DaB3eJ3gAcv_1 DaD04inv5-Z_1; do
        cp "$scratch/repo/SwingCoach/manual-cancel-fixture.mp4" "$scratch/repo/SwingCoach/ReferenceSwings/$name.mp4"
    done
fi
python3 "$repo/scripts/verification/inject-capture-controls-fixture.py" "$scratch/repo/SwingCoach/CaptureView.swift"

device=$(xcrun simctl create "SwingCoach Capture Controls $(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
{
    echo "route=disposable Simulator; driver=XCUITest; device_readiness=not-needed"
    echo "simulator=$device; fixture=synthetic file output, bundled reference review, deterministic detector snapshots"
    echo "hardware_recording=unverified; human_actions=none; suite=$suite"
    echo "test_selectors=${test_selectors[*]}"
    echo "actions=portrait lock across tabs/Trim/review,Auto/Manual layout,settings persistence,stats on/off,record/stop/Trim/Cancel,disabled/unavailable/waiting/error states,review playback/paging/deletion"
    xcrun simctl list devices | grep -F "$device"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/route.txt"
xcodebuild -project "$scratch/repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$artifacts/build.log" 2>&1
app="$scratch/DerivedData/Build/Products/Debug-iphonesimulator/SwingCoach.app"
python3 - "$app/Info.plist" > "$artifacts/orientation-policy.txt" <<'PY_POLICY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    info = plistlib.load(source)
for key in ['UISupportedInterfaceOrientations~iphone', 'UISupportedInterfaceOrientations~ipad']:
    assert info[key] == ['UIInterfaceOrientationPortrait'], (key, info.get(key))
    print(f'{key}={info[key]}')
assert info['UIRequiresFullScreen'] is True
print('PASS: built app permits upright portrait only on iPhone and iPad')
PY_POLICY
xcrun simctl install "$device" "$app"
xcrun simctl privacy "$device" grant photos Pear.ai.SwingCoach
xcrun simctl privacy "$device" grant photos-add Pear.ai.SwingCoach
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
    -parallel-testing-enabled NO -resultBundlePath "$artifacts/capture-controls.xcresult" \
    "${test_selectors[@]}" \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/test.log" 2>&1 || test_status=$?
xcrun xcresulttool get test-results summary --path "$artifacts/capture-controls.xcresult" > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$artifacts/capture-controls.xcresult" --output-path "$artifacts/screenshots" > /dev/null
xcrun simctl io "$device" screenshot "$artifacts/final-simulator.png"
[[ "$test_status" -eq 0 ]] || exit "$test_status"
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
python3 - "$container" "$artifacts/test-summary.json" "$expected_tests" <<'PY'
from pathlib import Path
import json, sys
root = Path(sys.argv[1])
summary = json.loads(Path(sys.argv[2]).read_text())
assert summary['passedTests'] == int(sys.argv[3]) and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
assert not list((root / 'tmp').glob('manual-cancel-*.mp4')), 'Cancelled recording was not removed'
print('PASS: all selected capture verification tests passed')
PY
