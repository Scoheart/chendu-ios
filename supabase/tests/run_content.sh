#!/usr/bin/env bash
# Reset the local database and assert content-table RLS.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
supabase db reset --yes
if command -v psql >/dev/null 2>&1; then
  psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
    -v ON_ERROR_STOP=1 \
    -f supabase/tests/content.sql
else
  docker exec -i supabase_db_chendu-ios \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
    < supabase/tests/content.sql
fi
echo "content tests passed"
