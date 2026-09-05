#!/bin/bash
set -euo pipefail
study=$(cd "$(dirname "$0")/.." && pwd)
media="${SWINGCOACH_PLAYGROUND_MEDIA:-$study/media}"
build="$study/.build"
app="$build/CaptureStudy.app"
mkdir -p "$app" "$build/SharedPlayer"
cp "$study/native/Info.plist" "$app/Info.plist"
python3 "$study/native/sync-player.py" "$build/SharedPlayer"

# Optional, locally owned imagery. A fresh checkout uses a neutral background.
rm -f "$app/camera.jpg"
if [[ -f "$media/camera.jpg" ]]; then cp "$media/camera.jpg" "$app/camera.jpg"; fi
for number in 001 002 003; do
    if [[ -f "$media/sample-$number.mp4" ]]; then
        cp "$media/sample-$number.mp4" "$app/sample-$number.mp4"
    else
        # Portable playback mechanics fixture, not footage for detector validation.
        ffmpeg -v error -y -f lavfi -i 'testsrc2=size=360x640:rate=30:duration=2' \
            -c:v libx264 -pix_fmt yuv420p "$app/sample-$number.mp4"
    fi
done
xcrun swiftc -parse-as-library -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -target "$(uname -m)-apple-ios26.0-simulator" -module-cache-path "$build/module-cache" \
    "$study/native/CaptureStudy.swift" "$study/native/StudyReview.swift" \
    "$build"/SharedPlayer/*.swift -o "$app/CaptureStudy"
codesign --force --sign - "$app"
echo "$app"
