#!/usr/bin/env bash
# Import the three JSON fixtures into local user A. Does not call the live site.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
supabase db reset --yes

if command -v psql >/dev/null 2>&1; then
  psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
    -v ON_ERROR_STOP=1 -f supabase/tests/import_setup.sql
else
  docker exec -i supabase_db_chendu-ios \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
    < supabase/tests/import_setup.sql
fi

set -a
# shellcheck disable=SC1090
source <(supabase status -o env)
set +a
export PATH="${HOME}/.deno/bin:${PATH}"
export SUPABASE_URL="${API_URL}"
export SUPABASE_SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY}"
deno run --allow-read --allow-env --allow-net packages/pipeline/import_integration.ts

if command -v psql >/dev/null 2>&1; then
  psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
    -v ON_ERROR_STOP=1 -f supabase/tests/import_assert.sql
else
  docker exec -i supabase_db_chendu-ios \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
    < supabase/tests/import_assert.sql
fi
echo "import tests passed"
