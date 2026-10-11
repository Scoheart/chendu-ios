#!/usr/bin/env bash
# Reject service-role markers in the iOS app and the web client.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-$root}"
python3 "$root/scripts/scan_secrets.py" "$target"
