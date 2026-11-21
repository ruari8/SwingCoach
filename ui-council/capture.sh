#!/bin/bash
# The UI council's deterministic screenshot run.
#
# Usage: ui-council/capture.sh <out-dir> [--ref <git-ref>]
#
# Builds the app (this checkout, or <git-ref> in a scratch worktree), installs
# it on one dedicated iPhone 17 Simulator with a pinned status bar, copies the
# seed library into the app container, and runs UICouncilTourUITests, which
# writes <out-dir>/<NN-screen>-<light|dark>.png. Every run uses the same
# Simulator model, the same seed and the same tour, so rounds are comparable.
#
# The seed is a coached range session that is not in git (it is Ruari's own
# footage and this repo is public). Build it once with:
#   detector_workbench/validation/coaching/run.sh <clips> <coached> --limit 0
#   python3 ui-council/tools/build_seed.py <session> <coached> <seed>
# and point UI_COUNCIL_SEED at <seed> (default ~/Documents/Startups/ui-council-media/seed).
set -euo pipefail

OUT="${1:?usage: capture.sh <out-dir> [--ref <git-ref>]}"
shift
REF=""
if [ "${1:-}" = "--ref" ]; then REF="$2"; fi

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SEED="${UI_COUNCIL_SEED:-$HOME/Documents/Startups/ui-council-media/seed}"
WORK="${UI_COUNCIL_WORK:-$HOME/Documents/Startups/ui-council-media/work}"
SIM_NAME="UI Council iPhone 17"
BUNDLE="Pear.ai.SwingCoach"
mkdir -p "$OUT" "$WORK"
OUT="$(cd "$OUT" && pwd)"
[ -f "$SEED/Documents/swing_library.json" ] || { echo "No seed at $SEED"; exit 2; }

# The checkout to build: this one, or the ref with the tour and fixture flag added.
SRC="$ROOT"
PLAN=OnRequest
if [ -n "$REF" ]; then
  PLAN=SwingCoach  # older plans do not list the tour; their default plan runs it
  SRC="$WORK/ref-$(git -C "$ROOT" rev-parse --short "$REF")"
  if [ ! -d "$SRC" ]; then
    git -C "$ROOT" worktree add --detach "$SRC" "$REF" >/dev/null
  fi
  cp "$ROOT/SwingCoachUITests/UICouncilTourUITests.swift" "$SRC/SwingCoachUITests/"
  if ! grep -q "ui-testing-auto-library" "$SRC/SwingCoach/CaptureView.swift"; then
    git -C "$SRC" apply "$HERE/tools/baseline-fixture.patch"
  fi
fi

# One Simulator, reused across rounds.
SIM=$(xcrun simctl list devices -j | python3 -c "
import json,sys
for runtime, devices in json.load(sys.stdin)['devices'].items():
    for d in devices:
        if d['name'] == '$SIM_NAME' and d['isAvailable']: print(d['udid']); sys.exit()
")
if [ -z "$SIM" ]; then
  SIM=$(xcrun simctl create "$SIM_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
fi
# A fresh boot per pass: the appearance setting can wedge and stop applying
# until the Simulator restarts.
fresh_boot() {
  xcrun simctl shutdown "$SIM" 2>/dev/null || true
  xcrun simctl boot "$SIM"
  xcrun simctl bootstatus "$SIM" -b >/dev/null
  xcrun simctl ui "$SIM" appearance "$1"
  xcrun simctl ui "$SIM" content_size large
  xcrun simctl status_bar "$SIM" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100
}
fresh_boot light
echo "Simulator $SIM"

DD="$WORK/dd-$(basename "$SRC")"
LOG="$OUT/xcodebuild.log"
cd "$SRC"
xcodebuild build-for-testing -project SwingCoach.xcodeproj -scheme SwingCoach \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO >"$LOG" 2>&1 \
  || { tail -30 "$LOG"; echo "BUILD FAILED"; exit 1; }

# Install, then replace the app's data with the seed. Reinstalling the same
# app later (the test runner does) keeps the data container.
APP=$(find "$DD/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name 'SwingCoach.app' | head -1)
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
# A golfer using the app has granted these; the tour should not show the prompts.
for service in photos camera microphone; do xcrun simctl privacy "$SIM" grant "$service" "$BUNDLE"; done
DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
rm -rf "$DATA/Documents" "$DATA/Library/Application Support" "$DATA/Library/Preferences/$BUNDLE.plist"
mkdir -p "$DATA/Library"
cp -R "$SEED/Documents" "$DATA/Documents"
cp -R "$SEED/Library/Application Support" "$DATA/Library/Application Support"

rm -f "$OUT"/*.png
for LOOK in ${UI_COUNCIL_APPEARANCES:-light dark}; do
  fresh_boot "$LOOK"
  TEST_RUNNER_UI_COUNCIL_OUT="$OUT" TEST_RUNNER_UI_COUNCIL_APPEARANCE="$LOOK" \
  xcodebuild test-without-building -project SwingCoach.xcodeproj -scheme SwingCoach -testPlan "$PLAN" \
    -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DD" \
    -only-testing:SwingCoachUITests/UICouncilTourUITests/testTour >>"$LOG" 2>&1 \
    || echo "Tour reported failures ($LOOK); see $LOG"
done
xcrun simctl status_bar "$SIM" clear
COUNT=$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "$COUNT screenshots in $OUT"
[ "$COUNT" -gt 0 ]
