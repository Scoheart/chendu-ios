#!/usr/bin/env bash
# Change learner fields the way Settings does, then let the worker snapshot them.
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
psql_run supabase/tests/settings_profile.sql

set -a
# shellcheck disable=SC1090
source <(supabase status -o env)
set +a
export PATH="${HOME}/.deno/bin:${PATH}"
export SUPABASE_URL="${API_URL}"
export SUPABASE_SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY}"
deno run --allow-read --allow-env --allow-net packages/pipeline/settings_integration.ts
echo "settings snapshot tests passed"
