# AGENTS.md

## Cursor Cloud specific instructions

This repo ("Barberya ni Tatis") is a monorepo with a shared **PHP 8 REST API** (`api/`),
a **PostgreSQL** database (`database/schema.pg.sql`), a static **web-admin/receptionist portal**
(`web-admin/`), and **Flutter** apps (`mobile-app/`, `kiosk/`). See `README.md` and `NOTES.txt`
for product context.

### What the update script already handles
On VM startup the update script runs `flutter pub get` for `mobile-app/` and `kiosk/`.
PHP has no Composer dependencies. System packages (PHP 8.3, PostgreSQL 16, Flutter) and the
seeded Postgres cluster persist in the VM snapshot — do not reinstall them.

### Starting services (NOT done automatically)
Services are not auto-started. Start them yourself each session:

- **PostgreSQL**: `sudo service postgresql start`
- **PHP API + web-admin**: serve the repo root so `api/*.php` and `web-admin/` are reachable
  under one origin: `php -S 0.0.0.0:8000` (run from `/workspace`). Portal login is then at
  `http://localhost:8000/web-admin/login.html`; the API is at `http://localhost:8000/api/`.

### Database / env notes
- The API reads DB credentials from a repo-root `.env` (git-ignored, so it is NOT in git but
  DOES persist in the snapshot). It contains `DB_URL=postgresql://tatis:tatis@127.0.0.1:5432/tatis_barbershop`.
  If `.env` is ever missing, recreate it with that line, then apply the schema and seed.
- Local DB setup (already applied, only needed on a fresh DB): role `tatis`/`tatis`, database
  `tatis_barbershop`, then
  `PGPASSWORD=tatis psql -h 127.0.0.1 -U tatis -d tatis_barbershop -f database/schema.pg.sql`
  and seed with `php scripts/seed_minimum_pg.php`.
- `db.php` picks the driver from the `DB_URL` scheme (`postgresql://` vs `mysql://`); the schema
  in use is `schema.pg.sql` (Postgres). `schema.sql` is a legacy MySQL variant — ignore it.
- Demo logins seeded by `seed_minimum_pg.php`: `admin@tatis.local / Admin123!`,
  `receptionist@tatis.local / Reception123!`, `barber@tatis.local / Barber123!`,
  `customer@tatis.local / Customer123!`.

### Non-obvious gotchas
- The **web-admin portal, PHP API, and Postgres are fully self-contained** and do NOT need
  Supabase. Web-admin login (`api/auth.php` action `login`) verifies password hashes directly
  against the DB. This is the stack to use for end-to-end backend testing.
- The **Flutter mobile app** initializes a hosted Supabase project (anon key hardcoded in
  `mobile-app/lib/main.dart`) for its own auth. Email/Google login there needs that external
  Supabase project + provisioned `auth.users`, which is not available in this environment, so a
  full mobile login/booking flow cannot be completed here. The app still builds and runs
  (`flutter build web` / `flutter run`) and renders its UI. Point it at the local API with
  `--dart-define=API_BASE_URL=http://localhost:8000/api`.
- Flutter is installed at `~/flutter` and added to `PATH` via `~/.bashrc`. `kiosk/` depends on
  `../mobile-app` via a path dependency, so run `flutter pub get` in `mobile-app/` first.
- PHP syntax lint: `find api scripts mobile-app/backend -name '*.php' -exec php -l {} \;`
  (there is no configured linter/test framework for PHP or the web portal).
