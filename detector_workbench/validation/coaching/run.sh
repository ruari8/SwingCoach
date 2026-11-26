#!/bin/sh
# Coaches a folder of saved down-the-line clips on this Mac with the app's own
# code and writes review sheets. See docs/COACHING.md.
#
# Usage: detector_workbench/validation/coaching/run.sh <clips-folder> <out-dir> [timeScale] [--limit N]
#   timeScale: how many times slower than real time the clips play (default 8,
#   a 240 fps capture). --limit N draws sheets for the first N+1 clips only.
set -e
if [ $# -lt 2 ]; then
  sed -n '2,8p' "$0"
  exit 2
fi
CLIPS="$1"; OUT="$2"; shift 2
SCALE=8
case "$1" in ''|--*) ;; *) SCALE="$1"; shift ;; esac
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD="${TMPDIR:-/tmp}/swingcoach-coaching-harness"
mkdir -p "$BUILD" "$OUT"
cd "$ROOT"
for model in SwingPositionTCN SwingObjectsYOLO11n; do
  [ -d "$BUILD/$model.mlmodelc" ] || xcrun coremlcompiler compile "SwingCoach/MLModels/$model.mlpackage" "$BUILD/" >/dev/null
done
# The store and the views need the app; everything else compiles on macOS.
swiftc -O -parse-as-library -suppress-warnings -o "$BUILD/harness" \
  SwingCoach/Models/CameraLensData.swift \
  SwingCoach/Models/SwingPositions/SwingPositions.swift \
  SwingCoach/Models/SwingPositions/SwingPositionAnalyzer.swift \
  SwingCoach/Models/GolfObjectDetector.swift \
  SwingCoach/Models/Coaching/Coaching*.swift \
  detector_workbench/validation/coaching/harness.swift
(
  set --
  for ext in mp4 MP4 mov MOV; do
    for f in "$CLIPS"/*."$ext"; do
      [ -e "$f" ] && set -- "$@" "$f"
    done
  done
  "$BUILD/harness" "$BUILD/SwingPositionTCN.mlmodelc" "$BUILD/SwingObjectsYOLO11n.mlmodelc" "$SCALE" "$OUT" "$@"
)
tools/venv/bin/python detector_workbench/validation/coaching/review.py "$OUT" "$@"
