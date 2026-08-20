#!/usr/bin/env bash
# Portable custom-format dump of the public schema.
# Does not run inside the PHP web request. Requires local/CI pg_dump.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

if [[ -z "${DB_DIRECT_URL:-}" ]]; then
  echo "Set DB_DIRECT_URL to the Supabase direct Postgres URL (db.<project-ref>.supabase.co:5432, sslmode=require)." >&2
  echo "Do not use the transaction pooler (port 6543). See docs/DATABASE_BACKUP.md" >&2
  exit 1
fi

if [[ "$DB_DIRECT_URL" == *":6543"* ]]; then
  echo "DB_DIRECT_URL looks like the transaction pooler (port 6543). pg_dump needs port 5432." >&2
  exit 1
fi

if ! command -v pg_dump >/dev/null 2>&1; then
  echo "pg_dump not found. Install PostgreSQL client tools." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to prepare the pg_dump connection." >&2
  exit 1
fi

CONN_ENV="$(mktemp)"
cleanup() { rm -f "$CONN_ENV"; }
trap cleanup EXIT

python3 "$ROOT/scripts/pg_dump_connection.py" >"$CONN_ENV"
unset PGHOST PGHOSTADDR PGPORT PGUSER PGPASSWORD PGDATABASE PGSSLMODE PGGSSENCMODE PGCONNECT_TIMEOUT BACKUP_CONN_KIND || true
# shellcheck disable=SC1090
source "$CONN_ENV"

OUT_DIR="${BACKUP_OUTPUT_DIR:-$ROOT/storage/backups}"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_FILE="$OUT_DIR/tatis_public_${STAMP}.dump"

# Discrete libpq vars (not a URI) so passwords with reserved characters work.
pg_dump \
  --schema=public \
  --no-owner \
  --no-acl \
  --format=custom \
  --file="$OUT_FILE"

echo "Wrote $(basename "$OUT_FILE") ($(wc -c < "$OUT_FILE") bytes)"
echo "Store this file off the Render API filesystem. Do not commit it."
