# Production deployment checklist (Web Admin + PHP API)

## Architecture

| Piece | Host | Notes |
|-------|------|--------|
| Web Admin (static HTML/JS) | Vercel (`web-admin/`) | Calls API cross-origin |
| PHP API | Render Docker (`api/`) | Supabase Postgres |
| AI sidecar | Render Python (`ai-service/`) | Optional try-on / face analysis |

Browser flow: `https://barberyanitatis.vercel.app` → `https://barberyanitatis.onrender.com/*.php`

Correct spelling everywhere: **barberyanitatis** (with **i**).

## Cold start (plain English)

On the **free** Render plan, the API goes to sleep when nobody uses it.

- First request after sleep **wakes** the server (often **30–90 seconds**).
- While it is waking, the browser may show **Failed to fetch**.
- That is usually **not** a broken database — wait and try again, or open the portal and wait ~1 minute before clicking Save / Manage / Calendar.

Paid Render plans can keep the service always on and avoid this.

## Deploy rule of thumb

| You changed… | Wait for… |
|--------------|-----------|
| `web-admin/` | **Vercel** only |
| `api/` | **Render** (PHP) |
| `ai-service/` | **Render** (sidecar) |
| both `web-admin/` and `api/` | **both** |

Then hard-refresh the portal (`Ctrl+Shift+R`) and test: https://barberyanitatis.vercel.app

## CORS note (important)

JSON POSTs from Vercel send a browser **OPTIONS** preflight. The API must answer OPTIONS with **204 + CORS headers**.  
Endpoints that only checked GET/POST used to return **405**, which the browser reports as **Failed to fetch**.  
`api/db.php` now answers OPTIONS for all scripts that include it.

## Production blockers / follow-ups

1. **Free Render sleep** — cold starts; consider always-on or a keep-alive ping.
2. **Uploads not persistent** — Docker filesystem is ephemeral. Production cutover uses **Supabase Storage** (`STORAGE_DRIVER=supabase` on Render). XAMPP stays `STORAGE_DRIVER=local`.
3. **Haircut overlay PNGs** — catalog PNGs were backfilled to `tatis-public`. New admin overlay uploads go to Storage when Render uses `STORAGE_DRIVER=supabase`.
4. **Secrets** — keep keys only in Render / local `.env`. Never commit `.env`. Rotate any key that was ever committed to git or embedded in frontend JS.
5. **Mobile / kiosk** — still need `--dart-define=API_BASE_URL=https://barberyanitatis.onrender.com` for production builds.
6. **PASSWORD_RESET_*** / Google client IDs** — set if those features are used in production.
7. **AI_SERVICE_URL** — must point at the public sidecar HTTPS URL on the PHP service.

## Local smoke checks (no deploy)

```bash
# From repo root / XAMPP: open web-admin via http://localhost/... (not file://)
# API relative paths should still resolve to /.../api/*.php

# Live API (after wake):
curl -s -o NUL -w "%{http_code}\n" https://barberyanitatis.onrender.com/ai_status.php
curl -s -o NUL -w "%{http_code}\n" -X OPTIONS https://barberyanitatis.onrender.com/admin_users.php
```

OPTIONS should return **204**. GET ai_status should return **200**.

---

## Phase 2 — Mobile app + kiosk (next)

Web admin is live. Point the Flutter apps at Render for real-device testing.

### Run against production API

From `mobile-app/`:

```powershell
# Interactive dev run (phone/emulator)
.\scripts\run_production.ps1

# Release APK
.\scripts\build_apk_production.ps1
```

Equivalent manual command:

```bash
flutter run --dart-define=USE_PRODUCTION_API=true
```

Kiosk uses the same `ApiConfig` via the `tatis_barbershop` package — same flags apply.

### Mobile test checklist

1. Login / register (customer)
2. Browse services & barbers
3. Book appointment (time slots)
4. Face scan / AI try-on (needs sidecar + Gemini keys on Render)
5. Payment flow (PayMongo keys if enabled)
6. Barber / receptionist roles if applicable

First API call after idle may take ~1 minute (cold start).

### Render disk for uploads (optional after Storage cutover)

With `STORAGE_DRIVER=supabase`, new images live in Supabase buckets. A Render disk at `/var/data` is optional (JSON partial exports / leftover local files). **Do not store the only production database backup on Render.**

Database disaster recovery (Supabase backups / PITR, portable `pg_dump`) is documented in [DATABASE_BACKUP.md](./DATABASE_BACKUP.md). The admin portal JSON tool is a **partial data export**, not a full backup.

---

## Phase 5 — Production storage cutover

Do **not** set `STORAGE_DRIVER=supabase` in local `.env`.

**On Render (PHP API), set:**

| Variable | Value |
|----------|--------|
| `STORAGE_DRIVER` | `supabase` |
| `SUPABASE_URL` | `https://<project>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` or `SUPABASE_SERVICE_ROLE` | service role (server only) |
| `SUPABASE_STORAGE_PUBLIC_BUCKET` | `tatis-public` |
| `SUPABASE_STORAGE_SCANS_BUCKET` | `tatis-scans` |

Then **redeploy the PHP service** so `docker-entrypoint.sh` writes those into `/var/www/.env`.

**Smoke after wake (production API, local app still `STORAGE_DRIVER=local`):**

1. Change a customer profile photo → file in `tatis-public/uploads/profiles/...`; DB still `uploads/profiles/...`
2. Change a barber photo → `tatis-public/uploads/barbers/...`
3. Face scan + try-on → `tatis-scans/uploads/face_scans/...`
4. Admin overlay upload → `tatis-public/assets/images/overlays/...`
5. Logout/login and appointment details still show photos

Local XAMPP: `flutter run` without `USE_PRODUCTION_API` still writes to disk.

### Security done in Phase 2 code

- Time-slot AI advice now calls **`chatbot.php`** on the server (no Gemini key in the app).
- Rotate any API key that was ever in git or frontend JS.

### Still manual / later

- Google OAuth redirect URLs for production mobile web
- PayMongo live keys
- App store / Play Store release builds
- Haircut overlay PNG upload in admin (needs `STORAGE_DRIVER=supabase` on Render after Phase 5)

