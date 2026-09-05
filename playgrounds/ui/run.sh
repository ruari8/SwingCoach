#!/bin/bash
set -euo pipefail
study=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$study/../.." && pwd)
case "${1:-native}" in
    web)
        exec python3 -m http.server "${2:-8768}" --bind 127.0.0.1 --directory "$study"
        ;;
    build)
        exec "$study/native/build.sh"
        ;;
    mirror)
        exec "$repo/scripts/mirror-ios-simulator.sh" "${2:?Pass a Simulator UDID}"
        ;;
    native) ;;
    *) echo "Usage: $0 [native [UDID] | build | web [port] | mirror UDID]" >&2; exit 2 ;;
esac
"$study/native/build.sh"
simulator="${2:-}"
owned=false
cleanup() {
    if [[ "$owned" == true ]]; then
        xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true
        xcrun simctl delete "$simulator" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
if [[ -z "$simulator" ]]; then
    simulator=$(xcrun simctl create "SwingCoach UI Playground $(date +%s)" \
        "${SWINGCOACH_PLAYGROUND_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17}")
    owned=true
fi
state=$(xcrun simctl list devices -j | python3 -c 'import json,sys; print(next(d["state"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["udid"] == sys.argv[1]))' "$simulator")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$simulator"; fi
xcrun simctl bootstatus "$simulator" -b
xcrun simctl install "$simulator" "$study/.build/CaptureStudy.app"
xcrun simctl launch --terminate-running-process "$simulator" dev.swingcoach.capturestudy
echo "UI playground simulator: $simulator"
echo "Open the URL printed below in the Codex browser. Ctrl-C ends this session."
"$repo/scripts/mirror-ios-simulator.sh" "$simulator"
