#!/bin/bash
set -euo pipefail

# Feed a labelled range video through Auto with the footage camera on a
# disposable Simulator, check every labelled swing is saved, and report
# delivery, drop, detector and save-latency metrics from the diagnostics log.
#
#   scripts/verify-footage-camera.sh [artifact-dir] [video-id]
#
# video-id is an entry in detector_workbench/validation/labels/
# detector_test_v3_labels.json (default test15: 71 s of 240 fps, 3 swings).
# The videos are private and gitignored, under .detectorTestV3/ in the main
# checkout. Vision pose does not run in the Simulator, so the detector rejects
# every swing there; Auto saves the labelled impacts instead and the detector's
# impact candidates are reported against the labels.
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/footage-camera/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
video_id="${2:-test15}"
mkdir -p "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-footage-camera.XXXXXX")
device=""
cleanup() {
    local status=$?
    local removed=true
    trap - EXIT
    if [[ -n "$device" ]]; then
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

# Footage and labels.
main_checkout=$(cd "$(git -C "$repo" rev-parse --git-common-dir)/.." && pwd)
labels="$repo/detector_workbench/validation/labels/detector_test_v3_labels.json"
eval "$(python3 - "$labels" "$video_id" <<'PY'
import json, sys
videos = {v['id']: v for v in json.load(open(sys.argv[1]))['videos']}
v = videos[sys.argv[2]]
scale = v['source_time_scale']
# Labels are source-timeline seconds; a bucket label covers [start, end].
impacts = [(l['start'] + l['end']) / 2 / scale for l in v['impact_time_labels']]
print(f"footage_file={v['filename']}")
print(f"time_scale={scale:g}")
print(f"expected={v['expected_swing_count']}")
print(f"impacts={','.join(f'{t:.4f}' for t in impacts)}")
PY
)"
footage=""
for candidate in "$repo/.detectorTestV3/$footage_file" "$main_checkout/.detectorTestV3/$footage_file"; do
    [[ -f "$candidate" ]] && footage="$candidate" && break
done
[[ -n "$footage" ]] || { echo "Missing footage .detectorTestV3/$footage_file" >&2; exit 1; }
footage_seconds=$(python3 -c "import sys; print(int(float(sys.argv[1]) / float(sys.argv[2])) + 1)" \
    "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$footage")" "$time_scale")

device=$(xcrun simctl create "SwingCoach Footage Camera $(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b > /dev/null
{
    echo "route=disposable Simulator; driver=XCUITest; device_readiness=not-needed"
    echo "simulator=$device; footage=$footage time_scale=$time_scale expected=$expected impacts=$impacts"
    echo "unverified_here=camera hardware, Vision pose detection, swing positions, phone speed and drops"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/route.txt"

xcodebuild -project "$repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$artifacts/build.log" 2>&1
app="$scratch/DerivedData/Build/Products/Debug-iphonesimulator/SwingCoach.app"
xcrun simctl install "$device" "$app"
xcrun simctl privacy "$device" grant photos Pear.ai.SwingCoach
xcrun simctl privacy "$device" grant photos-add Pear.ai.SwingCoach
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
mkdir -p "$container/Documents"
cp -c "$footage" "$container/Documents/$footage_file" 2>/dev/null || cp "$footage" "$container/Documents/$footage_file"

test_status=0
TEST_RUNNER_FOOTAGE_FILE="$footage_file" TEST_RUNNER_FOOTAGE_TIME_SCALE="$time_scale" \
TEST_RUNNER_FOOTAGE_IMPACTS="$impacts" TEST_RUNNER_FOOTAGE_EXPECTED="$expected" \
TEST_RUNNER_FOOTAGE_SECONDS="$footage_seconds" \
xcodebuild -project "$repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    -parallel-testing-enabled NO -resultBundlePath "$artifacts/footage-camera.xcresult" \
    -only-testing:SwingCoachUITests/FootageCameraUITests \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/test.log" 2>&1 || test_status=$?
xcrun xcresulttool get test-results summary --path "$artifacts/footage-camera.xcresult" > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$artifacts/footage-camera.xcresult" --output-path "$artifacts/screenshots" > /dev/null
# Installing the test build moves the app's data container; look it up again.
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
cp "$container/Library/Application Support/CaptureDiagnostics/capture.jsonl" "$artifacts/capture.jsonl" || true
[[ "$test_status" -eq 0 ]] || exit "$test_status"

python3 - "$artifacts" "$expected" "$impacts" <<'PY'
import json, sys
from pathlib import Path
artifacts, expected = Path(sys.argv[1]), int(sys.argv[2])
labels = [float(t) for t in sys.argv[3].split(',')]
summary = json.loads((artifacts / 'test-summary.json').read_text())
assert summary['passedTests'] == 1 and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
events = [json.loads(line) for line in (artifacts / 'capture.jsonl').read_text().splitlines()]
run = [e for e in events if e['boundary'] == 'footage-start'][-1]['runID']
events = [e for e in events if e['runID'] == run]
def find(boundary): return [e for e in events if e['boundary'] == boundary]

end = find('footage-end')
assert end, 'footage-end missing: the footage did not finish'
feed = end[-1]['values']
impacts, saved = find('footage-impact'), find('swing-saved')
assert len(impacts) == expected, f'{len(impacts)} labelled impacts declared, expected {expected}'
assert len(saved) == expected, f'{len(saved)} swings saved, expected {expected}'
for boundary in ('camera', 'detector', 'writer-start', 'export-written'):
    assert find(boundary), f'no {boundary} events in the diagnostics log'

# Each save follows its labelled impact: join impact -> export-start (detection id) -> swing-saved (chunk id).
starts = {e['state']['detection']: e for e in find('export-start')}
saved_by_chunk = {e['id']: e for e in saved}
latencies = []
for impact in impacts:
    start = starts[impact['id']]
    latencies.append(round(saved_by_chunk[start['id']]['uptime'] - impact['uptime'], 2))

# Detector decisions on the same timeline: impact candidates within 1 s of a label.
label_times = [e['values']['impactTime'] for e in impacts]
candidates = [e['values']['relativeTime'] for e in find('detector-state') if e['state']['state'] == 'impactCandidate']
found = sum(any(abs(c - t) <= 1.0 for c in candidates) for t in label_times)
camera = find('camera')
dropped = {}
for e in camera:
    for key, value in e['values'].items():
        if key.startswith('dropped_'): dropped[key[8:]] = dropped.get(key[8:], 0) + value
detector = find('detector')
mean_ms = [e['values'].get('meanInferenceMS', 0) for e in detector if e['values'].get('inferences')]
total = feed['delivered'] + feed['droppedOutOfBuffers'] + feed['droppedLate']
metrics = {
    'footageSeconds': round(feed['footageSeconds'], 1),
    'framesDelivered': int(feed['delivered']),
    'framesDroppedOutOfBuffers': int(feed['droppedOutOfBuffers']),
    'framesDroppedLate': int(feed['droppedLate']),
    'deliveredShare': round(feed['delivered'] / total, 3) if total else 0,
    'cameraDropSummary': dropped,
    'swingsExpected': expected,
    'swingsSaved': len(saved),
    'detectorImpactCandidates': len(candidates),
    'labelsWithDetectorCandidateWithin1s': found,
    'detectorSwingsAccepted': len(find('detector-swing')),
    'impactToSavedSeconds': latencies,
    'detectorMeanInferenceMS': round(sum(mean_ms) / len(mean_ms), 1) if mean_ms else None,
    'swingPositions': {'stored': len(find('swing-positions')), 'failed': len(find('swing-positions-failed'))},
}
(artifacts / 'metrics.json').write_text(json.dumps(metrics, indent=2))
print(json.dumps(metrics, indent=2))
print(f'PASS: {len(saved)}/{expected} labelled swings saved from footage; diagnostics log written')
PY
