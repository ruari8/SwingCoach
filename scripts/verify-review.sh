#!/bin/bash
set -euo pipefail

# All media and app state belong to this run's disposable Simulator. Synthetic
# videos keep these regressions runnable without private reference footage.
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/review-fixes/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-review.XXXXXX")
device=""
cleanup() {
    local status=$?
    local removed=true
    trap - EXIT
    if [[ -n "$device" ]]; then
        xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
        xcrun simctl delete "$device" >/dev/null 2>&1 || true
        if ! xcrun simctl list devices --json > "$artifacts/devices-after-cleanup.json" ||
            ! python3 - "$artifacts/devices-after-cleanup.json" "$device" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))['devices']
assert not any(d['udid'] == sys.argv[2] for group in devices.values() for d in group)
PY
        then
            removed=false
            status=1
        fi
    fi
    rm -rf "$scratch"
    echo "exit=$status owned_simulator=$device removed=$removed" > "$artifacts/cleanup.txt"
    exit "$status"
}
trap cleanup EXIT

command -v ffmpeg >/dev/null
device=$(xcrun simctl create "SwingCoach Review $(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
{
    echo "route=disposable Simulator; driver=XCTest; physical_device=none"
    echo "simulator=$device"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
    echo "fixtures=synthetic 360x640 video; three references; three personal clips"
} > "$artifacts/route.txt"

xcodebuild -project "$repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$artifacts/build.log" 2>&1
app="$scratch/DerivedData/Build/Products/Debug-iphonesimulator/SwingCoach.app"
xcrun simctl install "$device" "$app"
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)

ffmpeg -v error -f lavfi -i 'testsrc2=size=360x640:rate=30:duration=3' \
    -c:v libx264 -pix_fmt yuv420p "$scratch/review.mp4"
python3 - "$container" "$scratch/review.mp4" <<'PY'
import json, pathlib, shutil, sys
root, video = map(pathlib.Path, sys.argv[1:])
storage = root / 'Library/Application Support/SwingVideos'
storage.mkdir(parents=True, exist_ok=True)
shutil.copyfile(video, storage / 'review.mp4')
swings = []
for i, title, vantage, starred, reference, created in [
    (2, 'Review B Face-On', 'Face-On', False, False, 300),
    (1, 'Review A starred DTL', 'DTL', True, False, 200),
    (3, 'Review C DTL', 'DTL', False, False, 100),
    (4, 'Reference swing 1', 'DTL', True, True, 0),
    (5, 'Reference swing 2', 'DTL', True, True, 0),
    (6, 'Reference swing 3', 'DTL', True, True, 0),
]:
    swing_id = f'00000000-0000-0000-0000-{i:012d}'
    if reference:
        swing_id = f'93F08C01-6795-46B0-B092-7F9C17CE5A0{i-3}'
    swings.append(dict(id=swing_id, photoAssetID='', vantage=vantage,
        duration=3, createdAt=created, analyzed=False, isFavorite=starred,
        isReference=reference, title=title, localVideoFilename='review.mp4'))
(root / 'Documents').mkdir(exist_ok=True)
(root / 'Documents/swing_library.json').write_text(json.dumps(swings))
PY

{
    echo "simulator=$device"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist"
    echo "configuration=Debug"
    xcrun simctl launch --terminate-running-process "$device" Pear.ai.SwingCoach -ui-testing-library
} > "$artifacts/doctor.txt"
test_status=0
xcodebuild -project "$repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    -parallel-testing-enabled NO -resultBundlePath "$artifacts/review.xcresult" \
    -only-testing:SwingCoachTests/SwingReviewTests \
    -only-testing:SwingCoachUITests/LibraryReviewRegressionUITests \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/tests.log" 2>&1 || test_status=$?
xcrun xcresulttool get test-results summary --path "$artifacts/review.xcresult" > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$artifacts/review.xcresult" --output-path "$artifacts/screenshots" > /dev/null
[[ "$test_status" -eq 0 ]] || exit "$test_status"
python3 - "$artifacts/test-summary.json" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
assert summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
assert summary['passedTests'] == 7, summary
PY
echo "PASS: review regressions. Evidence: $artifacts"
