#!/bin/bash
set -euo pipefail

# Exercise production Trim and Photos export with synthetic camera/detector input.
# Capture the Coach handoff at the analysis boundary without network requests.
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/trim-review/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-trim-review.XXXXXX")
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
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$scratch/repo/SwingCoachUITests"
ditto "$repo/SwingCoach" "$scratch/repo/SwingCoach"
ditto "$repo/SwingCoach.xcodeproj" "$scratch/repo/SwingCoach.xcodeproj"
ditto "$repo/SwingCoachTests" "$scratch/repo/SwingCoachTests"
cp "$repo/scripts/verification/TrimReviewUITests.swift" "$scratch/repo/SwingCoachUITests/"
ffmpeg -v error -f lavfi -i 'testsrc2=size=160x280:rate=10:duration=310' \
    -f lavfi -i 'sine=frequency=440:duration=310' \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac "$scratch/repo/SwingCoach/trim-review-fixture.mp4"
python3 "$repo/scripts/verification/inject-trim-review-fixture.py" "$scratch/repo/SwingCoach"

device=$(xcrun simctl create "SwingCoach Trim Review $(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
{
    echo "route=disposable Simulator; driver=XCUITest; device_readiness=not-needed"
    echo "simulator=$device; fixture=synthetic 310-second video with audio; deterministic detections at 2,150,300 seconds"
    echo "hardware_recording=unverified; human_actions=none"
    echo "actions=Manual,record,stop,late selection,full review,swipe,export only,relaunch,subset analysis"
    xcrun simctl list devices | grep -F "$device"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/route.txt"
xcodebuild -project "$scratch/repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$artifacts/build.log" 2>&1
app="$scratch/DerivedData/Build/Products/Debug-iphonesimulator/SwingCoach.app"
xcrun simctl install "$device" "$app"
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
test_targets=(-only-testing:SwingCoachUITests/TrimReviewUITests)
if [[ "${SWINGCOACH_TRIM_VERIFY_UI_ONLY:-0}" != 1 ]]; then
    test_targets+=(-only-testing:SwingCoachTests/TrimClipPreparationTests)
fi
xcodebuild -project "$scratch/repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    -parallel-testing-enabled NO -resultBundlePath "$artifacts/trim-review.xcresult" \
    "${test_targets[@]}" \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/test.log" 2>&1 || test_status=$?
xcrun xcresulttool get test-results summary --path "$artifacts/trim-review.xcresult" > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$artifacts/trim-review.xcresult" --output-path "$artifacts/screenshots" > /dev/null
xcrun simctl io "$device" screenshot "$artifacts/final-simulator.png"
[[ "$test_status" -eq 0 ]] || exit "$test_status"
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
python3 - "$container" "$artifacts/test-summary.json" <<'PYTEST'
from pathlib import Path
import json, os, plistlib, sys
root = Path(sys.argv[1])
summary = json.loads(Path(sys.argv[2]).read_text())
assert summary['passedTests'] == (1 if os.environ.get('SWINGCOACH_TRIM_VERIFY_UI_ONLY') == '1' else 5) and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
prefs = plistlib.loads((root / 'Library/Preferences/Pear.ai.SwingCoach.plist').read_bytes())
ids = prefs.get('trim-verification-analysis-ids', [])
assert len(ids) == 1, ids
library_files = list((root / 'Documents').rglob('*.json'))
records = next(json.loads(p.read_text()) for p in library_files if p.name == 'swing_library.json')
assert len(records) == 6, records
assert any(record['id'] == ids[0] and record['localVideoFilename'] for record in records)
assert not list((root / 'tmp').glob('trim-review-*.mp4')), 'Completed recording was not removed'
print('PASS: timeline seek, full review, paging, export-only, subset handoff and 6 persisted local clips')
PYTEST
