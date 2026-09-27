#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/coaching/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
test_scope="${2:-all}"
mkdir -p "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-coaching.XXXXXX")
device=""
server=""
cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$server" ]]; then kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; fi
    if [[ -n "$device" ]]; then
        xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
        xcrun simctl delete "$device" >/dev/null 2>&1 || true
        xcrun simctl list devices --json > "$artifacts/devices-after-cleanup.json"
        python3 - "$artifacts/devices-after-cleanup.json" "$device" <<'PY' || status=1
import json,sys
assert not any(d['udid']==sys.argv[2] for group in json.load(open(sys.argv[1]))['devices'].values() for d in group)
PY
    fi
    rm -rf "$scratch"
    echo "exit=$status owned_simulator=$device server=$server cleanup=complete" > "$artifacts/cleanup.txt"
    exit "$status"
}
trap cleanup EXIT
"$repo/backend/venv/bin/python" "$repo/scripts/verification/coaching_backend.py" --storage "$artifacts/storage" --port 8871 > "$artifacts/backend.log" 2>&1 &
server=$!
python3 - "$server" <<'PY'
import json,sys,time,urllib.request
for _ in range(60):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8871/verification-ready') as response:
            assert json.load(response)['pid']==int(sys.argv[1]), 'Port belongs to another process'
        break
    except OSError:
        time.sleep(.5)
else: raise SystemExit('Verification backend did not start')
PY
ffmpeg -v error -ss 4 -i "$repo/SwingCoach/ReferenceSwings/DaBMIbhpel9_1.mp4" -t 4 \
    -vf 'scale=-2:640' -an -c:v libx264 -pix_fmt yuv420p "$scratch/swing.mp4"
device=$(xcrun simctl create "SwingCoach Coaching $$" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b > "$artifacts/boot.log"
{
    echo "route=disposable Simulator; driver=XCTest; phone=not-needed"
    echo "simulator=$device; backend=127.0.0.1:8871; storage=local; model=unavailable"
    echo "fixture=local reference crop 4-8 seconds; seeded source result is a contract fixture"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/route.txt"
xcodebuild -project "$repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$artifacts/build.log" 2>&1
app="$scratch/DerivedData/Build/Products/Debug-iphonesimulator/SwingCoach.app"
xcrun simctl install "$device" "$app"
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
"$repo/backend/venv/bin/python" - "$container" "$scratch/swing.mp4" "$repo" <<'PY'
import json,pathlib,shutil,sys
root,video,repo=map(pathlib.Path,sys.argv[1:])
sys.path.insert(0,str(repo/'backend'))
from analysis.coaching_contract import CoachingDetail, CoachingSource
from analysis.knowledge_library import KnowledgeLibrary
from analysis.coach_response_builder import intervention_text
storage=root/'Library/Application Support/SwingVideos'
storage.mkdir(parents=True,exist_ok=True)
(root/'Documents').mkdir(exist_ok=True)
swings=[]
for i,title in [(1,'Coaching upload fixture'),(2,'Coaching source fixture')]:
    uid=f'00000000-0000-0000-0000-{i:012d}'
    shutil.copyfile(video,storage/f'{uid}.mp4')
    swings.append(dict(id=uid,photoAssetID='',vantage='DTL',duration=4,createdAt=100-i,
                       analyzed=i==2,isFavorite=False,isReference=False,title=title,localVideoFilename=f'{uid}.mp4'))
(root/'Documents/swing_library.json').write_text(json.dumps(swings))
c=KnowledgeLibrary().cases['DcqwwGio81y-C02']
e=c['evidence'][1]
detail=CoachingDetail(status='recommend',focus='Backswing pivot · contract fixture',
    rationale='This saved fixture checks the coaching display; it is not a diagnosis of the fixture video.',
    cue=c['intervention']['cue'],reassess='Compare the intended movement and strike, then try without the prop.',
    sources=[CoachingSource(case_id=c['id'],title=c['title'],publisher=c['publisher'],url=c['source_url'],
              start_seconds=e['span_seconds'][0],end_seconds=e['span_seconds'][1],review_status=c['review_status'])],
    limitations=['Verification fixture. Live coaching model has not been called.'])
record=dict(id='10000000-0000-0000-0000-000000000002',swingID=swings[1]['id'],analysisID='source-fixture',createdAt=98,
    summary='Source-linked coaching display fixture',metrics=[],drills=[dict(title=c['title'],summary=intervention_text(c['intervention']))],
    coaching=detail.model_dump())
(root/'Documents/analysis_library.json').write_text(json.dumps([record]))
PY
{
    echo "simulator=$device configuration=Debug"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist"
    xcrun simctl launch "$device" Pear.ai.SwingCoach -ui-testing-library
} > "$artifacts/doctor.txt"
test_status=0
test_targets=(-only-testing:SwingCoachUITests/CoachingPipelineUITests)
expected_tests=1
if [[ "$test_scope" != ui ]]; then
    test_targets+=(-only-testing:SwingCoachTests/CoachingContractTests)
    expected_tests=3
fi
xcodebuild -project "$repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    -parallel-testing-enabled NO -resultBundlePath "$artifacts/coaching.xcresult" \
    "${test_targets[@]}" \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/tests.log" 2>&1 || test_status=$?
xcrun xcresulttool get test-results summary --path "$artifacts/coaching.xcresult" > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$artifacts/coaching.xcresult" --output-path "$artifacts/screenshots" > /dev/null
[[ "$test_status" -eq 0 ]] || exit "$test_status"
python3 - "$artifacts/test-summary.json" "$expected_tests" "$artifacts/storage" <<'PY'
import json,sys
from pathlib import Path
s=json.load(open(sys.argv[1]));assert s['failedTests']==0 and s['skippedTests']==0 and s['passedTests']==int(sys.argv[2]),s
metadata=list(Path(sys.argv[3]).rglob('input_meta.json'))
assert metadata, 'Missing persisted analysis input'
inputs=[json.loads(p.read_text()) for p in metadata]
assert any(m.get('student_goal')=='Improve contact' and m.get('golfer_context',{}).get('club')=='7 iron' for m in inputs), inputs
PY
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
cp "$container/Documents/analysis_library.json" "$artifacts/saved-analysis.json"
echo "PASS: real local upload, video analysis, overlay controls, sourced fixture and persistence. Evidence: $artifacts"
