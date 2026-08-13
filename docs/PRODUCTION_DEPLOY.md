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
2. **Uploads not persistent** — Docker filesystem is ephemeral; attach a Render disk for `uploads/` (and optionally `storage/`) or use object storage.
3. **Haircut overlay PNGs** — admin overlay upload expects `mobile-app/assets/...`, which is **not** in the API Docker image. Overlay **upload** will fail in production until assets are packaged or stored elsewhere. Metadata edit still works.
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
