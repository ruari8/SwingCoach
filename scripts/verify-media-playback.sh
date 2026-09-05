#!/bin/bash
set -euo pipefail

# Exercise actual player presentation and reject the reproduced frame-analysis
# diagnostics. Camera hardware diagnostics require a separate iPhone run.
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/media-playback/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
for fixture in DaB3eJ3gAcv_1.mp4 DaBMIbhpel9_1.mp4 DaD04inv5-Z_1.mp4; do
    [[ -f "$repo/SwingCoach/ReferenceSwings/$fixture" ]] || {
        echo "Missing local fixture: $fixture. See SwingCoach/ReferenceSwings/README.md." >&2
        exit 66
    }
done
mkdir -p "$(dirname "$artifacts")"
mkdir "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-media.XXXXXX")
device=""
log_pid=""
cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$log_pid" ]]; then
        kill "$log_pid" 2>/dev/null || true
        wait "$log_pid" 2>/dev/null || true
    fi
    if [[ -n "$device" ]]; then
        xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
        xcrun simctl delete "$device" >/dev/null 2>&1 || true
        if xcrun simctl list devices | grep -Fq "$device"; then status=1; fi
    fi
    rm -rf "$scratch"
    echo "exit=$status owned_simulator=$device" > "$artifacts/cleanup.txt"
    exit "$status"
}
trap cleanup EXIT

device=$(xcrun simctl create "SwingCoach Media $$" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
{
    echo "route=disposable Simulator; driver=XCUITest; phone_readiness=not-needed"
    echo "simulator=$device; bundle=Pear.ai.SwingCoach; configuration=Debug"
    echo "entry=Library launch argument; actions=paging,transport,drawing,playback,return to Library"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/route.txt"

xcrun simctl spawn "$device" log stream --level debug --style compact \
    --predicate 'process == "SwingCoach" AND (subsystem == "com.apple.VisionKit" OR subsystem == "com.apple.Translation" OR subsystem == "com.apple.coregraphics" OR subsystem == "Pear.ai.SwingCoach")' \
    > "$artifacts/system.log" 2>&1 &
log_pid=$!
test_status=0
xcodebuild -project "$repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    -parallel-testing-enabled NO -resultBundlePath "$artifacts/playback.xcresult" \
    -only-testing:SwingCoachUITests/LibraryPagingUITests/testPagingSettlesOnOneWholeVideo \
    -only-testing:SwingCoachUITests/LibraryPagingUITests/testQuarterPageDragCommitsAndSmallDragReturns \
    -only-testing:SwingCoachUITests/LibraryPagingUITests/testPlayerControlsStayOutsideMovingPages \
    -only-testing:SwingCoachUITests/LibraryPagingUITests/testOpeningMiddleSwingAndPlaybackGestures \
    -only-testing:SwingCoachUITests/LibraryPagingUITests/testPlaybackAdvancesAndReturnsToLibrary \
    CODE_SIGNING_ALLOWED=NO test > "$artifacts/test.log" 2>&1 || test_status=$?
# A dead log stream must not produce a false green result.
kill -0 "$log_pid"
kill "$log_pid"
wait "$log_pid" || true
log_pid=""
xcrun xcresulttool get test-results summary --path "$artifacts/playback.xcresult" > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$artifacts/playback.xcresult" --output-path "$artifacts/screenshots" >/dev/null
[[ "$test_status" -eq 0 ]] || exit "$test_status"
python3 - "$artifacts" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
summary = json.loads((root / 'test-summary.json').read_text())
assert summary['passedTests'] == 5 and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
log = (root / 'system.log').read_text()
assert 'SwingCoach[' in log, 'No app log events captured; cannot assess framework diagnostics'
markers = ['VKCImageAnalyzerRequest', 'Error processing request from MAD',
           'Visual isTranslatable', 'verify_image_parameters: invalid image']
counts = {marker: log.count(marker) for marker in markers}
(root / 'console-summary.json').write_text(json.dumps(counts, indent=2) + '\n')
assert not any(counts.values()), counts
assert 'TrimView.swift:' not in '\n'.join(line for line in (root / 'test.log').read_text().splitlines()
                                        if 'warning:' in line), 'TrimView compiler warning returned'
print('PASS: paging, transport, advancing playback; no reproduced frame-analysis diagnostics')
PY
echo "Evidence: $artifacts"
