# Database backup and recovery

This is **not** a complete product disaster-recovery solution by itself.
A `public` schema dump does not restore Supabase Auth or Storage files.

Treat backup files as sensitive. They contain customer data and password hashes.
Do not commit dumps, `DB_URL`, `DB_DIRECT_URL`, or service-role keys to Git.

---

## 1. Primary production recovery — Supabase

Use **Supabase Dashboard → Database → Backups** (and Point-in-Time Recovery if your plan includes it).

- This is the primary way to recover the hosted Postgres project.
- It stays **outside the application**. There is no admin UI button that restores production.
- Retention and PITR depend on the Supabase plan. Confirm in the dashboard.

Restore through Supabase’s own flow onto the intended project. Never paste a dump into a browser.

Nightly portable dumps (GitHub Actions → private Storage) are documented in [section 2b](#2b-automatic-production-pg_dump-github-actions). They do not replace this primary path.

---

## 2. Secondary portable backup — `pg_dump` (`public` schema)

Custom-format dump of the **application schema only**.

### Connection

The PHP API uses the Supabase **session pooler** (`DB_URL`, host `*.pooler.supabase.com`).

`pg_dump` must use the **direct** database host:

- Host: `db.<project-ref>.supabase.co`
- Port: `5432`
- `sslmode=require`
- Env var: `DB_DIRECT_URL` (see `.env.example`)

Do **not** use the transaction pooler (`port 6543`). Do not hardcode passwords.

Set `DB_DIRECT_URL` in your local environment or CI secrets. Do not set it on Render unless you are running a dedicated backup job off the web request path (this repo does not run `pg_dump` from PHP).

### What is included

Everything in `public` that `pg_dump --schema=public` captures, including:

- All public tables and rows (no 2,000-row cap)
- Primary keys, foreign keys, constraints, indexes
- Identity / sequence state
- Views (for example `queue_display`)
- Functions and triggers in `public`

The dump file does **not** contain `DB_URL`, service-role keys, or API secrets.

### What is not included

| Asset | Recover separately |
|---|---|
| Supabase Auth (`auth` schema, `auth.users`) | Supabase Auth / project backup |
| Storage buckets `tatis-public`, `tatis-scans` | Supabase Storage; do not dump `storage` schema into the app |
| Render ephemeral disk | Not a backup location |

### Create a dump (administrator machine or CI)

Requires `pg_dump` (PostgreSQL client tools), not the Render PHP container.

**Linux / macOS / CI**

```bash
export DB_DIRECT_URL="postgresql://postgres.<project-ref>:<password>@db.<project-ref>.supabase.co:5432/postgres?sslmode=require"
./scripts/backup_public_schema.sh
```

**Windows (PowerShell)**

```powershell
$env:DB_DIRECT_URL = "postgresql://postgres.<project-ref>:<password>@db.<project-ref>.supabase.co:5432/postgres?sslmode=require"
.\scripts\backup_public_schema.ps1
```

Equivalent command:

```bash
pg_dump "$DB_DIRECT_URL" \
  --schema=public \
  --no-owner \
  --no-acl \
  --format=custom \
  --file="tatis_public_YYYYMMDD_HHMMSS.dump"
```

Store the `.dump` file **off Render** (encrypted disk, object storage, or your backup vault). Do not keep the only copy on the API container.

---

## 2b. Automatic production `pg_dump` (GitHub Actions)

A scheduled workflow runs **outside Render** and does not use the PHP API:

- File: `.github/workflows/db-backup.yml`
- Script: `scripts/scheduled_pg_dump_backup.sh` (calls `scripts/backup_public_schema.sh`)
- Schedule: **daily at 18:00 UTC** (02:00 Asia/Manila)
- Manual run: GitHub → Actions → **Scheduled database backup** → Run workflow

### Storage

Dumps are uploaded to a **private** Supabase Storage bucket (default `tatis-backups`, prefix `pg_dump/`). That is persistent object storage, not Render’s container disk.

A second copy is kept as a GitHub Actions artifact for **14 days** (anyone with repo access can download it).

Do not put dumps in `tatis-public`. Keep `tatis-backups` private.

### Secrets (GitHub repo → Settings → Secrets and variables → Actions)

| Secret | Purpose |
|---|---|
| `DB_DIRECT_URL` | Direct Postgres URL: `db.<project-ref>.supabase.co:5432?sslmode=require` |
| `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role — server only |

Never commit these values. The workflow does not echo connection strings.

### Retention

- Default: **14 days**, and **at least the 7 newest** dumps even if older
- Prune runs after a successful upload
- GitHub artifact copy: 14 days

### Failure handling

- `pg_dump` failure, empty/tiny dump, missing secrets, or Storage upload failure **fails the job**
- No dump is uploaded if the dump file is invalid
- Enable GitHub email/Slack notifications on failed workflows so a missed night is noticed
- This job is **secondary**. If it fails, production recovery is still **Supabase Backups / PITR**

### First-time setup

1. Add the three secrets above.
2. In Supabase, confirm Storage is enabled. The script creates private bucket `tatis-backups` if needed.
3. Run the workflow once with **Run workflow** and confirm a `.dump` appears in Storage.
4. Confirm GitHub Actions is allowed to run on `main` (Actions tab not disabled).

GitHub-hosted runners can usually reach the **direct** DB host. If DNS/IPv6 fails, do not switch to pooler port `6543`. Fix IPv6 or use the session pooler host on port **5432** only as a last resort.

---

## 3. Portable restore — staging first

Do **not** restore production from the admin portal. Do **not** `TRUNCATE CASCADE` production from HTTP.

1. Obtain a `.dump` file:
   - Automatic: Supabase Storage → private bucket `tatis-backups` → `pg_dump/…`, or the workflow artifact
   - Manual: `scripts/backup_public_schema.sh`
2. Restore into a **separate / staging** database:

```bash
pg_restore \
  --clean \
  --if-exists \
  --no-owner \
  --no-acl \
  --dbname="$STAGING_DB_URL" \
  tatis_public_YYYYMMDD_HHMMSS.dump
```

3. Verify tables, foreign keys, sequences, views, and functions.
4. Point a staging API at that database and confirm the app works.
5. Only then perform a **controlled** production recovery (prefer Supabase PITR/backups; use `pg_restore` only with a documented maintenance window).

`$STAGING_DB_URL` must also be a direct (or session) Postgres URL with SSL, never a secret committed to Git.

Download example (run locally; do not paste a real service-role key into chat or Git):

```bash
curl -L -o tatis_public.dump \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  "$SUPABASE_URL/storage/v1/object/authenticated/tatis-backups/pg_dump/tatis_public_YYYYMMDD_HHMMSS.dump"
```

---

## 4. JSON tool in the admin portal

The Settings page **Partial data export** is unchanged in purpose:

- Tables: `users`, `barbers`, `staff_users`, `services`, `appointments`, `appointment_details`, `time_slots`, `notifications`, `system_settings`
- Cap: **2,000 rows per table**
- Format: JSON
- **Not** a full database backup

### CASCADE restore risk

JSON restore runs `TRUNCATE … RESTART IDENTITY CASCADE` on the tables in the file.

PostgreSQL then also empties **other tables that reference those rows**. Walk-ins, payments, group bookings, feedback, scans, and similar data can disappear even though they were never in the JSON file.

Use JSON restore only for small application-data copies, never as production DR.

Export/restore endpoints require an **Admin** portal session (server-side). Unsigned GET/POST requests receive `401` or `403`.

---

## 5. Authorization

Staff login (`auth.php`) issues a random portal session token (hash stored in `portal_sessions`, 12-hour expiry).

The admin portal sends `Authorization: Bearer <token>` (and `X-Portal-Token`) on API calls.

`admin_settings.php` (settings, CSV export, JSON export/restore) calls `require_admin()` and allows only active `staff_users.role = Admin`.

Receptionists and unauthenticated clients are rejected. Frontend hiding of the Settings page is not sufficient by itself.
