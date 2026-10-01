#!/usr/bin/env bash
# Scheduled production backup: pg_dump public schema, upload to a PRIVATE
# Supabase Storage bucket, prune old dumps. Does not run in the PHP web process.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export BACKUP_OUTPUT_DIR="${BACKUP_OUTPUT_DIR:-$ROOT/storage/backups}"
export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
export BACKUP_KEEP_MIN="${BACKUP_KEEP_MIN:-7}"
export BACKUP_STORAGE_BUCKET="${BACKUP_STORAGE_BUCKET:-tatis-backups}"
export BACKUP_STORAGE_PREFIX="${BACKUP_STORAGE_PREFIX:-pg_dump}"

if [[ "${BACKUP_RETENTION_DAYS}" -lt 3 ]]; then
  echo "BACKUP_RETENTION_DAYS must be at least 3." >&2
  exit 1
fi

bash "$ROOT/scripts/backup_public_schema.sh"

DUMP="$(ls -1t "$BACKUP_OUTPUT_DIR"/tatis_public_*.dump 2>/dev/null | head -n 1 || true)"
if [[ -z "$DUMP" || ! -s "$DUMP" ]]; then
  echo "pg_dump did not produce a dump file." >&2
  exit 1
fi

SIZE="$(wc -c < "$DUMP" | tr -d ' ')"
if [[ "$SIZE" -lt 1024 ]]; then
  echo "Dump file is too small (${SIZE} bytes); refusing to upload." >&2
  exit 1
fi

export BACKUP_DUMP_PATH="$DUMP"
export BACKUP_DUMP_SIZE="$SIZE"

if [[ -z "${SUPABASE_URL:-}" ]]; then
  echo "SUPABASE_URL is required to store dumps off-site." >&2
  exit 1
fi
if [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-${SUPABASE_SERVICE_ROLE:-}}" ]]; then
  echo "SUPABASE_SERVICE_ROLE_KEY is required to store dumps off-site." >&2
  exit 1
fi

python3 - <<'PY'
import json, os, urllib.error, urllib.request
from datetime import datetime, timedelta, timezone

dump = os.environ["BACKUP_DUMP_PATH"]
size = int(os.environ["BACKUP_DUMP_SIZE"])
bucket = os.environ.get("BACKUP_STORAGE_BUCKET", "tatis-backups")
prefix = os.environ.get("BACKUP_STORAGE_PREFIX", "pg_dump").strip("/") + "/"
retention_days = int(os.environ.get("BACKUP_RETENTION_DAYS", "14"))
keep_min = int(os.environ.get("BACKUP_KEEP_MIN", "7"))
base = os.environ["SUPABASE_URL"].rstrip("/")
key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get("SUPABASE_SERVICE_ROLE") or ""
object_path = prefix + os.path.basename(dump)

def req(method, url, data=None, headers=None, binary=False, allow_http=()):
    hdrs = {"Authorization": "Bearer " + key, "apikey": key}
    if headers:
        hdrs.update(headers)
    body = data
    if data is not None and not binary and not isinstance(data, (bytes, bytearray)):
        body = json.dumps(data).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    request = urllib.request.Request(url, data=body, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(request, timeout=180) as resp:
            raw = resp.read()
            if not raw:
                return {}
            try:
                return json.loads(raw.decode("utf-8"))
            except json.JSONDecodeError:
                return {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        if exc.code in allow_http:
            return {"error": True, "status": exc.code, "detail": detail}
        # The body is the only thing that says WHY. It carries no secrets --
        # without it a failure reads as a bare "(400)" and costs a round trip
        # through the Actions log to diagnose.
        raise SystemExit(
            f"Storage API {method} failed ({exc.code}): {detail}"
        ) from None

# No file_size_limit: a per-bucket limit above the project's global upload
# limit is rejected with 400, and that 400 used to be swallowed as "already
# exists" -- so the bucket was never created and every upload since failed
# against a bucket that was not there.
#
# 400 is allowed here all the same, because Supabase reports an existing bucket
# as HTTP 400 with a body of {"statusCode":"409","code":"BucketAlreadyExists"} --
# the status line alone cannot tell "already there" from "refused". Nothing is
# masked by allowing it: the GET below is what decides whether the bucket is
# really there, and it reports Storage's own reason when it is not.
req(
    "POST",
    f"{base}/storage/v1/bucket",
    {"id": bucket, "name": bucket, "public": False},
    allow_http=(400, 409),
)

# Creation is not assumed to have worked. If the bucket is still missing the
# upload cannot succeed, and failing here names the real cause.
existing = req(
    "GET",
    f"{base}/storage/v1/bucket/{bucket}",
    allow_http=(400, 404),
)
if existing.get("error"):
    raise SystemExit(
        f"Private bucket {bucket} does not exist and could not be created: "
        + str(existing.get("detail") or "no detail from Storage")
    )
if existing.get("public"):
    raise SystemExit(
        f"Bucket {bucket} is PUBLIC. Dumps contain customer data and password "
        "hashes; refusing to upload. Make it private in Supabase Storage."
    )

with open(dump, "rb") as fh:
    payload = fh.read()
uploaded = req(
    "POST",
    f"{base}/storage/v1/object/{bucket}/{object_path}",
    payload,
    {"Content-Type": "application/octet-stream", "x-upsert": "true"},
    binary=True,
    allow_http=(409,),
)
if uploaded.get("status") == 409:
    # Same filename already there (a re-run inside the same second). Overwrite.
    req(
        "PUT",
        f"{base}/storage/v1/object/{bucket}/{object_path}",
        payload,
        {"Content-Type": "application/octet-stream", "x-upsert": "true"},
        binary=True,
    )
print(f"Uploaded {object_path} ({size} bytes) to private bucket {bucket}")

listed = req(
    "POST",
    f"{base}/storage/v1/object/list/{bucket}",
    {"prefix": prefix, "limit": 1000, "offset": 0, "sortBy": {"column": "created_at", "order": "desc"}},
)
if not isinstance(listed, list):
    print("Could not list existing dumps; skipping prune.")
    raise SystemExit(0)

objects = []
for item in listed:
    name = str(item.get("name") or "")
    if not name.endswith(".dump"):
        continue
    created_at = item.get("created_at") or item.get("updated_at") or ""
    objects.append((name, created_at))
objects.sort(key=lambda row: row[1], reverse=True)

cutoff = datetime.now(timezone.utc) - timedelta(days=retention_days)
kept = 0
deleted = 0
for index, (name, created_at) in enumerate(objects):
    keep_newest = index < keep_min
    too_old = False
    if created_at:
        try:
            parsed = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
            too_old = parsed < cutoff
        except ValueError:
            too_old = False
    if keep_newest or not too_old:
        kept += 1
        continue
    key_path = name if name.startswith(prefix) else prefix + name
    req("DELETE", f"{base}/storage/v1/object/{bucket}/{key_path}")
    deleted += 1
    print(f"Pruned {key_path}")

print(f"Retention: {retention_days} days, keep at least {keep_min} dumps. Kept {kept}, pruned {deleted}.")
PY
