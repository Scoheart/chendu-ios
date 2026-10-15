#!/usr/bin/env bash
# Request a local magic link, read it from Inbucket, and verify. Prints only the user id.
set -euo pipefail
email="${1:-a@example.com}"
if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "Set SUPABASE_URL and SUPABASE_ANON_KEY. Do not pass the service role." >&2
  exit 1
fi
curl -fsS -X POST "${SUPABASE_URL}/auth/v1/otp" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "content-type: application/json" \
  -d "{\"email\":\"${email}\",\"create_user\":true}" >/dev/null

SUPABASE_URL="$SUPABASE_URL" SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" python3 - "$email" <<'PY'
import json, os, re, sys, time, urllib.request
email = sys.argv[1]
base = os.environ["SUPABASE_URL"]
anon = os.environ["SUPABASE_ANON_KEY"]
deadline = time.time() + 20
message_id = None
while time.time() < deadline and not message_id:
    with urllib.request.urlopen("http://127.0.0.1:54324/api/v1/messages") as response:
        payload = json.load(response)
    for row in payload.get("messages", []):
        blob = json.dumps(row.get("To"))
        if email in blob:
            message_id = row["ID"]
            break
    if not message_id:
        time.sleep(0.4)
if not message_id:
    sys.exit("no mail in Inbucket")
with urllib.request.urlopen(f"http://127.0.0.1:54324/api/v1/message/{message_id}") as response:
    mail = json.load(response)
match = re.search(r"token=([^&\s]+)", mail.get("Text") or mail.get("HTML") or "")
if not match:
    sys.exit("mail had no token")
body = json.dumps({"type": "magiclink", "token_hash": match.group(1)}).encode()
request = urllib.request.Request(
    f"{base}/auth/v1/verify",
    data=body,
    headers={"apikey": anon, "content-type": "application/json"},
)
with urllib.request.urlopen(request) as response:
    session = json.load(response)
user_id = session.get("user", {}).get("id")
if not user_id:
    sys.exit("verify returned no user")
print(user_id)
PY
