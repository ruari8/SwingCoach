#!/bin/bash
set -euo pipefail

# Verify Library session grouping, session Select, slide-to-select and batch
# export on an owned Simulator seeded with two sessions of local-only clips.
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/library-sessions/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-library-sessions.XXXXXX")
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
cp "$repo/scripts/verification/LibrarySessionsUITests.swift" "$scratch/repo/SwingCoachUITests/"
ffmpeg -v error -f lavfi -i 'testsrc2=size=360x640:rate=30:duration=1' \
    -c:v libx264 -pix_fmt yuv420p "$scratch/fixture.mp4"

device=$(xcrun simctl create "SwingCoach Library Sessions $(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
{
    echo "route=disposable Simulator; driver=XCUITest; device_readiness=not-needed"
    echo "simulator=$device; fixture=6 local clips today, 3 yesterday; real Library, selection and export"
    echo "human_actions=none"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/route.txt"
xcodebuild -project "$scratch/repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$artifacts/build.log" 2>&1
app="$scratch/DerivedData/Build/Products/Debug-iphonesimulator/SwingCoach.app"
xcrun simctl install "$device" "$app"
xcrun simctl privacy "$device" grant photos Pear.ai.SwingCoach
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
python3 - "$container" "$scratch/fixture.mp4" <<'PY'
import json, shutil, sys, uuid
from datetime import datetime, timedelta
from pathlib import Path

container, fixture = Path(sys.argv[1]), sys.argv[2]
videos = container / "Library/Application Support/SwingVideos"
videos.mkdir(parents=True, exist_ok=True)
(container / "Documents").mkdir(parents=True, exist_ok=True)
apple_epoch = datetime(2001, 1, 1).astimezone()
now = datetime.now().astimezone()
today = now.replace(hour=12, minute=0, second=0, microsecond=0)
if now < today:
    today -= timedelta(hours=2)
times = [today + timedelta(minutes=2 * i) for i in range(6)]
times += [today - timedelta(days=1) + timedelta(minutes=2 * i) for i in range(3)]
swings = []
for created in times:
    swing_id = str(uuid.uuid4()).upper()
    shutil.copy(fixture, videos / f"{swing_id}.mp4")
    swings.append({
        "id": swing_id, "photoAssetID": "", "vantage": "DTL", "duration": 1.0,
        "createdAt": (created - apple_epoch).total_seconds(), "analyzed": False,
        "isFavorite": False, "isReference": False, "localVideoFilename": f"{swing_id}.mp4",
    })
(container / "Documents/swing_library.json").write_text(json.dumps(swings))
PY
{
    echo "simulator=$device configuration=Debug container=$container"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist"
    git -C "$repo" rev-parse HEAD
} > "$artifacts/doctor.txt"
test_status=0
xcodebuild -project "$scratch/repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    -parallel-testing-enabled NO -resultBundlePath "$artifacts/test.xcresult" \
    -only-testing:SwingCoachUITests/LibrarySessionsUITests -only-testing:SwingCoachTests/SwingSessionTests \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/test.log" 2>&1 || test_status=$?
xcrun xcresulttool get test-results summary --path "$artifacts/test.xcresult" > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$artifacts/test.xcresult" --output-path "$artifacts/screenshots" > /dev/null
xcrun simctl io "$device" screenshot "$artifacts/final-simulator.png"
[[ "$test_status" -eq 0 ]] || exit "$test_status"
echo "PASS: session select, slide-to-select, vertical scroll and export share sheet"
