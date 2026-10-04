#!/usr/bin/env bash
# Serve the analysis backend from this Mac for the app on a phone on the same Wi-Fi.
# Coach model calls go through `codex exec` and the signed-in ChatGPT plan, not API billing.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
port="${PORT:-8000}"
ip=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
codex login status >/dev/null 2>&1 || { echo "Run 'codex login' first." >&2; exit 1; }
echo "In the app: Library → gear icon → Backend target: Custom → http://$ip:$port"
SWINGCOACH_COACH_PROVIDER=codex exec "$repo/backend/venv/bin/python" \
    "$repo/scripts/verification/coaching_backend.py" \
    --storage "$repo/backend/output/local-app" --host 0.0.0.0 --port "$port" \
    --public-url "http://$ip:$port"
