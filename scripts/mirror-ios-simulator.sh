#!/bin/bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <owned-or-exclusively-used-simulator-UDID>" >&2
    exit 2
fi
simulator=$1
export npm_config_cache="${SWINGCOACH_MIRROR_NPM_CACHE:-${TMPDIR:-/tmp}/swingcoach-simulator-mirror-npm}"
mirror=(npx --yes serve-sim@0.1.46)
cleanup() { "${mirror[@]}" --kill "$simulator" >/dev/null 2>&1 || true; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
# Reclaim helpers only for this explicitly selected simulator.
cleanup
"${mirror[@]}" "$simulator"
