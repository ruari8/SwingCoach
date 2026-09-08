#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
artifacts="${1:-$repo/.verification-artifacts/trim-playback-clock/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$artifacts"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/trim-playback-clock.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
ffmpeg -v error -f lavfi -i 'color=black:size=64x64:rate=240:duration=4' \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$scratch/clock.mp4"
swiftc "$repo/SwingCoach/Models/TrimTimecode.swift" "$repo/scripts/verification/TrimPlaybackClockProbe.swift" -o "$scratch/probe"
if "$scratch/probe" "$scratch/clock.mp4" --legacy-interval > "$artifacts/before.txt"; then
    echo 'FAIL: legacy interval did not reproduce the timer jumps'; exit 1
fi
"$scratch/probe" "$scratch/clock.mp4" > "$artifacts/after.txt"
cat "$artifacts/after.txt"
echo 'PASS: real slow-motion playback clock advances in tenths'
