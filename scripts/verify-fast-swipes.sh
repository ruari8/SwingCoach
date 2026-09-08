#!/bin/bash
set -euo pipefail

# A long collection exposes momentum skipping hidden by end-of-list clamping.
# All videos and Library state are synthetic and belong to this simulator.
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/fast-swipes/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
command -v ffmpeg >/dev/null
mkdir -p "$(dirname "$artifacts")"
mkdir "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-flick.XXXXXX")
device=""
cleanup() {
    local status=$?
    local simulator_absent=not-created
    trap - EXIT
    if [[ -n "$device" ]]; then
        xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
        xcrun simctl delete "$device" >/dev/null 2>&1 || true
        if xcrun simctl list devices | grep -Fq "$device"; then
            status=1
            simulator_absent=false
        else
            simulator_absent=true
        fi
    fi
    rm -rf "$scratch"
    echo "exit=$status owned_simulator=$device simulator_absent_after_delete=$simulator_absent" > "$artifacts/cleanup.txt"
    exit "$status"
}
trap cleanup EXIT

device=$(xcrun simctl create "SwingCoach Fast Swipes $$" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
{
    echo "route=disposable Simulator; driver=XCUITest; phone_readiness=not-needed"
    echo "simulator=$device; bundle=Pear.ai.SwingCoach; configuration=Debug"
    echo "fixtures=171 synthetic reference videos; no Photos writes"
    echo "entry=Library launch argument and Auto review fixture"
    echo "gestures=left/right flicks at 1500,3000,6000 points per second; latest boundary; reopen, delete, append"
    echo "simulator_os=$(xcrun simctl getenv "$device" SIMULATOR_RUNTIME_VERSION)"
    echo "human_actions=none"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/route.txt"
xcodebuild -project "$repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$artifacts/build.log" 2>&1
xcrun simctl install "$device" "$scratch/DerivedData/Build/Products/Debug-iphonesimulator/SwingCoach.app"
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
ffmpeg -v error -f lavfi -i 'testsrc2=size=360x640:rate=30:duration=3' \
    -c:v libx264 -pix_fmt yuv420p "$scratch/fixture.mp4"
python3 - "$container" "$scratch/fixture.mp4" <<'PY'
import json, pathlib, shutil, sys
root, source = map(pathlib.Path, sys.argv[1:])
storage = root / 'Library/Application Support/SwingVideos'
storage.mkdir(parents=True, exist_ok=True)
bundled_names = ['DaB3eJ3gAcv_1.mp4', 'DaBMIbhpel9_1.mp4', 'DaD04inv5-Z_1.mp4']
swings = []
for i in range(1, 172):
    uid = f'93F08C01-6795-46B0-B092-7F9C17CE5A0{i}' if i <= 3 else f'00000000-0000-0000-0000-{i:012d}'
    filename = bundled_names[i - 1] if i <= 3 else uid + '.mp4'
    shutil.copyfile(source, storage / filename)
    swings.append(dict(id=uid, photoAssetID='', vantage='DTL', duration=3,
                       createdAt=172-i, analyzed=False, isFavorite=True, isReference=True,
                       title=f'Reference swing {i}', localVideoFilename=filename))
(root / 'Documents').mkdir(exist_ok=True)
(root / 'Documents/swing_library.json').write_text(json.dumps(swings))
PY
# Verify the installed Debug instance before XCTest drives the seeded session.
launch_output=$(xcrun simctl launch "$device" Pear.ai.SwingCoach -ui-testing-auto-review)
installed_app=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach app)
installed_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Info.plist")
simulator_line=$(xcrun simctl list devices | grep -F "$device")
launch_services=$(xcrun simctl spawn "$device" launchctl print user/501)
[[ "$installed_bundle" == "Pear.ai.SwingCoach" && "$simulator_line" == *"(Booted)"* ]]
grep -Fq 'Pear.ai.SwingCoach' <<< "$launch_services"
tcc_db="$HOME/Library/Developer/CoreSimulator/Devices/$device/data/Library/TCC/TCC.db"
tcc_rows=$(sqlite3 -readonly "$tcc_db" "SELECT service || '=' || auth_value FROM access WHERE client = 'Pear.ai.SwingCoach' ORDER BY service;" 2>/dev/null || true)
{
    echo "simulator=$simulator_line"
    echo "bundle_id=$installed_bundle; configuration=Debug"
    echo "launch=$launch_output"
    echo "running_bundle=Pear.ai.SwingCoach verified-in-launch-services"
    echo "photos_authorization_raw=${tcc_rows:-notDetermined}"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/doctor.txt"
xcrun simctl io "$device" screenshot "$artifacts/launch.png"
test_status=0
xcodebuild -project "$repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    -parallel-testing-enabled NO -resultBundlePath "$artifacts/swipes.xcresult" \
    -only-testing:SwingCoachUITests/FastSwipePagingUITests \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/test.log" 2>&1 || test_status=$?
xcrun xcresulttool get test-results summary --path "$artifacts/swipes.xcresult" > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$artifacts/swipes.xcresult" --output-path "$artifacts/screenshots" >/dev/null
xcrun simctl io "$device" screenshot "$artifacts/final-simulator.png"
[[ "$test_status" -eq 0 ]] || exit "$test_status"
python3 - "$artifacts/test-summary.json" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
assert summary['passedTests'] == 3 and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
print('PASS: one video per fast flick; Auto review latest entry, reopening, deletion and simulated new clip')
PY
echo "Evidence: $artifacts"
