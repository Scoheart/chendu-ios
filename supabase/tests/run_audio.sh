#!/usr/bin/env bash
# Service role uploads; the owner can sign a URL; another user cannot.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
supabase db reset --yes

set -a
# shellcheck disable=SC1090
source <(supabase status -o env)
set +a

owner="11111111-1111-4111-8111-111111111111"
other="22222222-2222-4222-8222-222222222222"
issue="dddddddd-dddd-4ddd-8ddd-dddddddddddd"
object="${owner}/${issue}/normal.mp3"
payload="$(mktemp)"
printf 'mp3-bytes' > "$payload"

code="$(curl -sS -o /tmp/chendu-audio-upload.json -w '%{http_code}' \
  -X POST "${API_URL}/storage/v1/object/audio/${object}" \
  -H "authorization: Bearer ${SERVICE_ROLE_KEY}" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H 'content-type: audio/mpeg' \
  -H 'x-upsert: true' \
  --data-binary @"$payload")"
if [[ "$code" != "200" ]]; then
  echo "upload failed: ${code}" >&2
  cat /tmp/chendu-audio-upload.json >&2
  exit 1
fi

sign() {
  local uid="$1"
  local jwt
  jwt="$(python3 - "$uid" "$JWT_SECRET" <<'PY'
import base64, hashlib, hmac, json, sys, time
uid, secret = sys.argv[1], sys.argv[2]
def b64(raw: bytes) -> bytes:
    return base64.urlsafe_b64encode(raw).rstrip(b"=")
header = b64(b'{"alg":"HS256","typ":"JWT"}')
payload = b64(json.dumps({
    "aud": "authenticated",
    "role": "authenticated",
    "sub": uid,
    "exp": int(time.time()) + 3600,
}, separators=(",", ":")).encode())
sig = b64(hmac.new(secret.encode(), header + b"." + payload, hashlib.sha256).digest())
sys.stdout.write((header + b"." + payload + b"." + sig).decode())
PY
)"
  curl -sS -o /tmp/chendu-audio-sign.json -w '%{http_code}' \
    -X POST "${API_URL}/storage/v1/object/sign/audio/${object}" \
    -H "authorization: Bearer ${jwt}" \
    -H "apikey: ${ANON_KEY}" \
    -H 'content-type: application/json' \
    -d '{"expiresIn":60}'
}

owner_code="$(sign "$owner")"
if [[ "$owner_code" != "200" ]]; then
  echo "owner sign failed: ${owner_code}" >&2
  cat /tmp/chendu-audio-sign.json >&2
  exit 1
fi
python3 - <<'PY'
import json
body = json.load(open("/tmp/chendu-audio-sign.json"))
url = body.get("signedURL") or body.get("signedUrl") or ""
if "/object/sign/" not in url:
    raise SystemExit(f"missing signed url: {body}")
open("/tmp/chendu-audio-signed-path", "w").write(url)
PY
signed="$(cat /tmp/chendu-audio-signed-path)"
down="$(curl -sS -o /tmp/chendu-audio-body -w '%{http_code}' "${API_URL}/storage/v1${signed}")"
if [[ "$down" != "200" ]]; then
  echo "download failed: ${down}" >&2
  exit 1
fi
if [[ "$(cat /tmp/chendu-audio-body)" != "mp3-bytes" ]]; then
  echo "downloaded body mismatch" >&2
  exit 1
fi

other_code="$(sign "$other")"
if [[ "$other_code" == "200" ]]; then
  echo "other user signed the same object" >&2
  cat /tmp/chendu-audio-sign.json >&2
  exit 1
fi

rm -f "$payload" /tmp/chendu-audio-upload.json /tmp/chendu-audio-sign.json /tmp/chendu-audio-signed-path /tmp/chendu-audio-body
echo "audio tests passed"
