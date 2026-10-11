#!/usr/bin/env bash
# The clean tree passes. A planted marker fails. A library prefix check does not.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/scan_secrets.sh"

leak="$(mktemp -d)"
mkdir -p "$leak/Chendu"
printf '%s\n' 'let leaked = "service_role"' > "$leak/Chendu/Leak.swift"
if "$root/scripts/scan_secrets.sh" "$leak"; then
  echo "scanner missed a planted service role" >&2
  exit 1
fi

prefix="$(mktemp -d)"
mkdir -p "$prefix/apps/web"
printf '%s\n' 'const check = value.startsWith("sb_secret_")' > "$prefix/apps/web/prefix.js"
"$root/scripts/scan_secrets.sh" "$prefix"

echo "secret scan tests passed"
