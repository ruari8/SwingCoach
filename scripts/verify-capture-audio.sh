#!/bin/bash
set -euo pipefail

# Verify audio policy on real preview entry points and scoped recording audio.
# Only authorization and camera file output are substituted in a scratch copy.
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/capture-audio/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/swingcoach-capture-audio.XXXXXX")
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
cp "$repo/scripts/verification/CaptureAudioUITests.swift" "$repo/scripts/verification/ManualTrimCancelUITests.swift" "$scratch/repo/SwingCoachUITests/"
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
# Exercise configure() without a physical camera or permission prompt. Keep
# production start(), configure(), stop(), Auto, and navigation intact.
source = source.replace('AVCaptureDevice.authorizationStatus(for: .video)',
                        'AVAuthorizationStatus.authorized')
source = source.replace('    private func configureAndStartSession() {',
                        '    private func configureAndStartSession() {\n        defer { publishAudioVerification() }')
source = source.replace('    private var isConfigured = false', '''    private let initialAudioCategory = AVAudioSession.sharedInstance().category
    private let initialAudioMode = AVAudioSession.sharedInstance().mode
    private let initialAudioOptions = AVAudioSession.sharedInstance().categoryOptions
    @Published var captureAudioVerification = "pending"
    private var verificationStarts = 0
    private func publishAudioVerification() {
        verificationStarts += 1
        let audio = AVAudioSession.sharedInstance()
        let unchanged = audio.category == initialAudioCategory && audio.mode == initialAudioMode
            && audio.categoryOptions == initialAudioOptions
        let microphones = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
            .filter { $0.device.hasMediaType(.audio) }.count
        let summary = "unchanged=\\(unchanged) microphones=\\(microphones) starts=\\(verificationStarts)"
        DispatchQueue.main.async { self.captureAudioVerification = summary }
    }
    private var isConfigured = false''')
source = source.replace('        .preferredColorScheme(.dark)\n        .onAppear {', '''        .overlay(alignment: .center) {
            Text(camera.captureAudioVerification)
                .accessibilityIdentifier("capture-audio-verification")
        }
        .preferredColorScheme(.dark)
        .onAppear {''', 1)
path.write_text(source)
PY

device=$(xcrun simctl create "SwingCoach Capture Audio $(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
{
    echo "route=disposable Simulator; driver=XCUITest; device_readiness=not-needed"
    echo "simulator=$device; fixture=authorized video boundary, read-only audio-policy instrumentation, synthetic Manual file output"
    echo "hardware_recording=unverified; human_actions=none"
    echo "actions=launch,Auto/Manual tab reentry,relaunch,audio ownership unit tests,Manual record/stop/Trim/Cancel"
    xcrun simctl list devices | grep -F "$device"
    git -C "$repo" rev-parse HEAD
    git -C "$repo" status --short
} > "$artifacts/route.txt"
xcodebuild -project "$scratch/repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$artifacts/build.log" 2>&1
app="$scratch/DerivedData/Build/Products/Debug-iphonesimulator/SwingCoach.app"
xcrun simctl install "$device" "$app"
# A single formerly crashing test gates every later app launch. Omit all retry
# and repetition flags, with no other selected test for Xcode to restart.
smoke_status=0
xcodebuild -project "$scratch/repo/SwingCoach.xcodeproj" -scheme SwingCoach -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$scratch/DerivedData" \
    -parallel-testing-enabled NO \
    -resultBundlePath "$artifacts/audio-smoke.xcresult" \
    -only-testing:SwingCoachTests/CaptureRecordingAudioSessionTests/testConstructionAndIdleReleaseDoNotTouchAudio \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/audio-smoke.log" 2>&1 || smoke_status=$?
xcrun xcresulttool get test-results summary --path "$artifacts/audio-smoke.xcresult" > "$artifacts/audio-smoke-summary.json"
[[ "$smoke_status" -eq 0 ]] || exit "$smoke_status"
python3 - "$artifacts/audio-smoke-summary.json" <<'PYSMOKE'
import json, sys
from pathlib import Path
summary = json.loads(Path(sys.argv[1]).read_text())
assert summary['passedTests'] == 1 and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
print('PASS: isolated audio helper construction and release; continuing remaining tests')
PYSMOKE
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
    -parallel-testing-enabled NO \
    -resultBundlePath "$artifacts/capture-audio.xcresult" \
    -only-testing:SwingCoachUITests/ManualTrimCancelUITests \
    -only-testing:SwingCoachUITests/CaptureAudioUITests \
    -only-testing:SwingCoachTests/CaptureRecordingAudioSessionTests \
    -skip-testing:SwingCoachTests/CaptureRecordingAudioSessionTests/testConstructionAndIdleReleaseDoNotTouchAudio \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$artifacts/test.log" 2>&1 || test_status=$?
xcrun xcresulttool get test-results summary --path "$artifacts/capture-audio.xcresult" > "$artifacts/test-summary.json"
xcrun xcresulttool export attachments --path "$artifacts/capture-audio.xcresult" --output-path "$artifacts/screenshots" > /dev/null
xcrun simctl io "$device" screenshot "$artifacts/final-simulator.png"
[[ "$test_status" -eq 0 ]] || exit "$test_status"
container=$(xcrun simctl get_app_container "$device" Pear.ai.SwingCoach data)
python3 - "$container" "$artifacts/test-summary.json" <<'PY'
from pathlib import Path
import json, sys
root = Path(sys.argv[1])
summary = json.loads(Path(sys.argv[2]).read_text())
assert summary['passedTests'] == 6 and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
assert not list((root / 'tmp').glob('manual-cancel-*.mp4')), 'Cancelled recording was not removed'
print('PASS: preview audio policy, scoped recording audio, Manual/Trim/Cancel and file cleanup')
PY
