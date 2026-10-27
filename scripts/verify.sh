#!/bin/bash
# The one entry point for SwingCoach verification. See `scripts/verify.sh --help`.
exec python3 -I "$(dirname "$0")/verification/verify.py" "$@"
