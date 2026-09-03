# Barberya ni Tatis

Barbershop management system with AI-assisted haircut recommendation and virtual try-on.

The system covers four audiences from one codebase and one database:

| Audience | Client | Auth |
|---|---|---|
| Customers | Flutter mobile app | Supabase Auth |
| Barbers | Flutter mobile app (barber dashboard) | Supabase Auth |
| Admin / Receptionist | Web portal (`web-admin/`) | PHP API session + portal token |
| Walk-in kiosk | Flutter kiosk app | Device-local, no user login |

---

## Architecture

```
Flutter mobile app ─┐
Flutter kiosk app  ─┼──►  PHP REST API (api/)  ──►  Supabase Postgres
Web admin portal   ─┘            │
                                 ├──►  AI sidecar (ai-service/)   face + hair analysis
                                 ├──►  Gemini / Grok / Replicate  try-on image generation
                                 ├──►  Supabase Storage           scan + preview images
                                 └──►  PayMongo                   payments

Flutter mobile app ─────────────────►  Supabase Auth   (sign-in, sessions, recovery)
```

Two things are deliberately separate:

- **Authentication** for mobile customers and barbers goes directly to **Supabase Auth**. The PHP API never holds their passwords; it maps a verified email to an application account.
- **Application data** (appointments, services, barbers, scans) goes through the **PHP API**, which owns all business rules and database access.

## Tech stack

- **Flutter** 3.x (Dart SDK `^3.5.2`) — mobile app and kiosk
- **PHP 8.2** — REST API, PDO over Postgres
- **Python / FastAPI** — AI sidecar for face and hair analysis (MediaPipe)
- **Supabase** — Auth, Postgres, Storage
- **Vanilla JS + HTML/CSS** — admin and receptionist portals (no framework, no build step)
- **Render** — hosts the PHP API and the AI sidecar (Docker)
- **Vercel** — hosts the web admin portal

---

## Repository structure

```
api/            PHP REST API — auth, appointments, scans, payments, admin endpoints
ai-service/     Python FastAPI sidecar — face shape + hair texture analysis
mobile-app/     Flutter app for customers and barbers (also builds the kiosk variant)
kiosk/          Standalone Flutter kiosk app
web-admin/      Admin + receptionist portals (static HTML/JS)
database/       Postgres schema and migrations
scripts/        Provisioning and maintenance scripts
docs/           Deployment, database backup, scan pipeline, API spec
```

---

## Local setup

### Prerequisites

- XAMPP (Apache + PHP 8.2) or any PHP 8.2 host
- Flutter SDK 3.x
- Python 3.10+ (only if running the AI sidecar locally)
- A Supabase project (Auth + Postgres + Storage)

### 1. Environment

Copy the template and fill it in. **`.env` is gitignored — never commit it.**

```bash
cp .env.example .env
```

Minimum to boot the API:

```
DB_URL=postgresql://<user>:<password>@<host>:5432/postgres?sslmode=require
```

### 2. Database

Apply the schema to your Postgres database:

```bash
psql "$DB_URL" -f database/schema.pg.sql
```

Migrations live in `database/migrations/`.

### 3. PHP API

Serve the repository from XAMPP's `htdocs`. The API is then reachable at:

```
http://localhost/barberyanitatis/tatis_barbershop/api/
```

Verify with `http://localhost/.../api/ai_status.php` — it returns a JSON health summary.

### 4. Mobile app

```bash
cd mobile-app
flutter pub get
flutter run
```

The app resolves its API base URL automatically (`lib/user/api_config.dart`):

| Target | API base URL |
|---|---|
| Web / iOS simulator | `http://localhost/.../api` |
| Android emulator | `http://10.0.2.2/.../api` |
| Physical device | `http://<LAN_HOST>/.../api` |

For a physical device, pass your PC's current LAN IP:

```bash
flutter run --dart-define=LAN_HOST=192.168.1.x
```

To run against the deployed Render API instead:

```bash
.\scripts\run_production.ps1
```

Release build:

```bash
.\scripts\build_apk_production.ps1
```

### 5. AI sidecar (optional locally)

```bash
cd ai-service
pip install -r requirements.txt
uvicorn api:app --host 127.0.0.1 --port 8000
```

Then set `AI_SERVICE_URL=http://127.0.0.1:8000` in `.env`. Without it, face scanning falls back to the profile's stored hair-type estimate instead of live analysis.

### 6. Web admin portal

Open `web-admin/login.html` through the web server (not as a `file://` URL). It auto-detects the API: same-origin on `localhost`, otherwise the production Render URL.

---

## Configuration reference

All server configuration is read from `.env` locally, and from the **Render dashboard** in production. See `.env.example` for the full list.

| Variable | Purpose |
|---|---|
| `DB_URL` | Postgres connection string |
| `AI_SERVICE_URL` | AI sidecar base URL |
| `GEMINI_API_KEY`, `GEMINI_MODEL` | Face-scan analysis and chatbot |
| `AI_TRYON_PROVIDER` | `grok`, `gemini`, or `replicate` |
| `XAI_API_KEY`, `GROK_IMAGE_MODEL` | Grok try-on image generation |
| `REPLICATE_API_TOKEN`, `REPLICATE_FLUX_MODEL` | Replicate try-on |
| `STORAGE_DRIVER` | `supabase` in production, local disk on XAMPP |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | Server-side Auth admin + Storage |
| `GOOGLE_ALLOWED_CLIENT_IDS` | Accepted Google OAuth audiences |
| `PASSWORD_RESET_BASE_URL`, `PASSWORD_RESET_MAIL_FROM` | Legacy PHP recovery (mobile uses Supabase) |
| `PAYMONGO_SECRET` | Payments |
| `BOOKING_WINDOW_DAYS` | How far ahead customers may book |

> The Supabase **anon** key is intentionally embedded in the Flutter client. It is a public key protected by row-level security. The **service role** key must only ever live on the server.

---

## Authentication model

**Mobile (customers and barbers)** — Supabase Auth is the source of truth:

- Email/password, Google OAuth, and Facebook OAuth
- Password recovery by emailed code (entered in-app) or recovery link
- After sign-in, the app calls `auth.php` → `resolveAccount` to map the verified email to an application account and its roles
- `AuthBootstrap` (`mobile-app/lib/user/auth_bootstrap.dart`) centralises session handling, recovery-session binding, and post-login routing

**Web portal (admin and receptionist)** — PHP `auth.php` login returning a portal token held in `sessionStorage`. Every portal page re-validates on load and on browser back/forward.

---

## Deployment

- **PHP API** → Render web service, Docker, root `api/`, health check `/ai_status.php`
- **AI sidecar** → Render web service, Docker, root `ai-service/`, health check `/health`
- **Web admin** → Vercel (`web-admin/vercel.json`)
- **Database, Auth, Storage** → Supabase

`render.yaml` is a blueprint for both Render services. Secrets are **not** in it — set them in the Render dashboard.

Both Render services are on the **free plan**, which sleeps when idle. The first request after sleep can take 30–90 seconds, and free instance hours are capped per month. See `docs/PRODUCTION_DEPLOY.md`.

---

## Known issues

- **Repeat OAuth sign-in.** The first Google/Facebook sign-in per app launch succeeds; a second attempt in the same run fails with `flow_state_not_found`. Email/password is unaffected. Root cause unresolved — the `auth.flow_state` row exists in the database while the token endpoint reports it missing.
- **AI analysis unavailable.** When the AI sidecar returns HTTP 429 (free-tier quota exhausted), the health check requires a 2xx and reports *"AI analysis service is not running"* — the service is reachable, just rate-limited. Face scanning falls back to the stored hair-type estimate.
- **Try-on consistency.** Image generation passes no seed, so the same photo and style produce different results per run, and the three view angles are generated independently.

## Documentation

| Document | Contents |
|---|---|
| `docs/PRODUCTION_DEPLOY.md` | Render and Vercel deployment |
| `docs/DATABASE_BACKUP.md` | Backup and restore |
| `docs/SCAN_PIPELINE.md` | Face scan → analysis → try-on pipeline |
| `docs/api-spec.md` | API endpoint reference |
| `docs/AUTHENTICATION_FIX.md` | Auth troubleshooting history |

## Testing

```bash
cd mobile-app
flutter analyze
flutter test
```
