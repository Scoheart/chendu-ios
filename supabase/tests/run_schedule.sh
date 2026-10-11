#!/usr/bin/env bash
# Prove enqueue_due uses p_now, then the worker finishes the queued job.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
supabase db reset --yes

psql_run() {
  if command -v psql >/dev/null 2>&1; then
    psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f "$1"
  else
    docker exec -i supabase_db_chendu-ios psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$1"
  fi
}

psql_run supabase/tests/schedule_setup.sql
psql_run supabase/tests/schedule.sql

if grep -Ei 'tts|mp3|synthesize|audio/speech' supabase/functions/run-jobs/index.ts; then
  echo "run-jobs must only enqueue" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source <(supabase status -o env)
set +a
export PATH="${HOME}/.deno/bin:${PATH}"
export SUPABASE_URL="${API_URL}"
export SUPABASE_SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY}"
deno run --allow-read --allow-env --allow-net packages/pipeline/schedule_integration.ts
echo "schedule tests passed"
