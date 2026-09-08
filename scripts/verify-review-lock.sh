#!/bin/bash
set -euo pipefail

# Prove review-session Lock through Library and the production Auto review fixture.
# All videos and Library state are synthetic and belong to this simulator.
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/review-lock/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
command -v ffmpeg >/dev/null
mkdir -p "$(dirname "$artifacts")"
mkdir "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-lock.XXXXXX")
device=""
cleanup() {
    local status=$?
    local removed=not-created
    trap - EXIT
    if [[ -n "$device" ]]; then
        xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
        xcrun simctl delete "$device" >/dev/null 2>&1 || true
        if xcrun simctl list devices > "$artifacts/devices-after-cleanup.txt" &&
            ! grep -Fq "$device" "$artifacts/devices-after-cleanup.txt"; then
            removed=true
        else
            removed=false
            status=1
        fi
    fi
    rm -rf "$scratch"
    echo "exit=$status owned_simulator=$device simulator_absent_after_delete=$removed" > "$artifacts/cleanup.txt"
    exit "$status"
}
trap cleanup EXIT

device=$(xcrun simctl create "SwingCoach Review Lock $$" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
{
    echo "route=disposable Simulator; driver=XCUITest; phone_readiness=not-needed"
    echo "simulator=$device; bundle=Pear.ai.SwingCoach; configuration=Debug"
    echo "fixtures=3 synthetic reference videos; no Photos writes"
    echo "entry=Library launch argument and Auto review fixture"
    echo "actions=lock,paging forward/back,playback,unlock,paging,reopen Library review"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/route.txt"
xcodebuild -project "$repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$artifacts/build.log" 2>&1
xcrun simctl install "$device" "$scratch/DerivedData/Build/Products/Debug-iphonesimulator/SwingCoach.app"
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
ffmpeg -v error -f lavfi -i 'testsrc2=size=360x640:rate=30:duration=12' \
    -c:v libx264 -pix_fmt yuv420p "$scratch/fixture.mp4"
python3 - "$container" "$scratch/fixture.mp4" <<'PY'
import json, pathlib, shutil, sys
root, source = map(pathlib.Path, sys.argv[1:])
storage = root / 'Library/Application Support/SwingVideos'
storage.mkdir(parents=True, exist_ok=True)
bundled_names = ['DaB3eJ3gAcv_1.mp4', 'DaBMIbhpel9_1.mp4', 'DaD04inv5-Z_1.mp4']
swings = []
for i in range(1, 4):
    uid = f'93F08C01-6795-46B0-B092-7F9C17CE5A0{i}'
    filename = bundled_names[i - 1]
    shutil.copyfile(source, storage / filename)
    swings.append(dict(id=uid, photoAssetID='', vantage='DTL', duration=12,
                       createdAt=4-i, analyzed=False, isFavorite=True, isReference=True,
                       title=f'Reference swing {i}', localVideoFilename=filename))
(root / 'Documents').mkdir(exist_ok=True)
(root / 'Documents/swing_library.json').write_text(json.dumps(swings))
PY
installed_app=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach app)
installed_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Info.plist")
simulator_line=$(xcrun simctl list devices | grep -F "$device")
launch=$(xcrun simctl launch --terminate-running-process "$device" Pear.ai.SwingCoach -ui-testing-library)
launch_services=$(xcrun simctl spawn "$device" launchctl print user/501)
[[ "$installed_bundle" == "Pear.ai.SwingCoach" && "$simulator_line" == *"(Booted)"* ]]
grep -Fq "$installed_bundle" <<< "$launch_services"
tcc_db="${HOME}/Library/Developer/CoreSimulator/Devices/$device/data/Library/TCC/TCC.db"
tcc_rows=$(sqlite3 -readonly "$tcc_db" "SELECT service || '=' || auth_value FROM access WHERE client = '$installed_bundle' ORDER BY service;" 2>/dev/null || true)
{
    echo "simulator=$simulator_line"
    echo "os=$(xcrun simctl getenv "$device" SIMULATOR_RUNTIME_VERSION)"
    echo "bundle=$installed_bundle; configuration=Debug"
    echo "launch=$launch; process_confirmed=true"
    echo "photos_authorization_raw=${tcc_rows:-notDetermined}"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/doctor.txt"
xcrun simctl io "$device" screenshot "$artifacts/launch.png"
test_status=0
xcodebuild -project "$repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    -parallel-testing-enabled NO -resultBundlePath "$artifacts/lock.xcresult" \
    -only-testing:SwingCoachUITests/ReviewLockUITests \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/test.log" 2>&1 || test_status=$?
xcrun xcresulttool get test-results summary --path "$artifacts/lock.xcresult" > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$artifacts/lock.xcresult" --output-path "$artifacts/screenshots" >/dev/null
xcrun simctl io "$device" screenshot "$artifacts/final-simulator.png"
[[ "$test_status" -eq 0 ]] || exit "$test_status"
python3 - "$artifacts/test-summary.json" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
assert summary['passedTests'] == 2 and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
print('PASS: Lock and explicit unlock persist across Library and Auto paging; new Library review resets Lock')
PY
echo "Evidence: $artifacts"
