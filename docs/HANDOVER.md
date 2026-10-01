# Handover — Brilliante Barbershop

Branch: `claude/friendly-rubin-iovthr`.

**Merge status** (corrected — an earlier revision of this file wrongly said nothing was merged):
- The eight phase-1 commits `ecc461a`..`c368522` **are already in `main`**, via PR #4 and merge `7ce6d19`.
- `main` also carries `ec6e3bf` (book from saved look, suggested time on direct library booking, load times after picking a slot, paid appointment still reading as pending, bookings page loading) — work done outside this session.
- Still **not** in `main`: the `db89bff` hotfix, `8c951a9` (Top services), `45b618b` (admin auth) and this file. `main` therefore currently has the saved-look delete bug in its most visible form, because the change that made delete succeed is merged but the `setState` fix is not.
- `origin/main` has been merged into this branch (`fe3d896`) — clean, no file overlap — so this branch is one mergeable history.

Everything below is verified fact, not assumption.

---

## 1. What is shipped

All on `claude/friendly-rubin-iovthr`, one commit each, oldest first.

| Commit | What |
|---|---|
| `ecc461a` | Manage-haircut modal alignment + overlay preview URLs |
| `56deecb` | Sign-out confirmation, both portals |
| `61ee203` | Loading states on the haircuts screen |
| `f29a1eb` | Toasts render above modal dialogs |
| `9cb4efd` | "Exclude from Top 3" honoured on the Gemini path |
| `1e1faa7` | Saved-look delete: stale-id fix, idempotent 404 |
| `a6e4ab3` | Barber card: photo, info icon, richer profile dialog |
| `c368522` | Weather advice sentence written from real scoring data |
| `db89bff` | **Hotfix** — `setState` assertion on saved-look delete |
| `8c951a9` | Top services removed from Analytics |
| `45b618b` | **Admin API now requires an admin session** |

### Verified in this environment (do not re-verify)

- **Toast above modal** — pixel-compared with and without a modal open: byte-identical, so painted above the backdrop, undimmed. Also survives a second dialog opening on top.
- **Button loading** — `is-loading` + `disabled` + `aria-busy` during an awaited call; a second click mid-flight is ignored.
- **Top-3 exclusion** — 15 unit tests over the extracted helpers (Postgres `'t'`/`'f'` handling, excluded top scorer dropped, short-list behaviour, all-excluded → empty, backfill order, duplicate model picks).
- **Analytics layout** — at 1440px (above the 1240px `.split` breakpoint): status-mix card spans the full row, other `split-even` rows still side-by-side at half width.
- **Admin auth** — full matrix over HTTP against real Postgres, all 7 endpoints: 401 no token, 401 bad token, **403 valid receptionist token**, 200 valid admin token, via both `Bearer` and `X-Portal-Token`. Unauthenticated writes (user delete, hairstyle create, service create, overlay upload) return 401 and leave the DB untouched.

### NOT verified — needs a device (no Flutter toolchain in this environment)

Everything under `mobile-app/`: commits `1e1faa7`, `a6e4ab3`, `c368522`, `db89bff`.

Test list:
1. Saved tab → delete a look → **no error, card disappears immediately** (this is the hotfix).
2. Delete from the *detail* page → returns to the list with the card gone.
3. Delete the same look twice → second attempt silent.
4. Save a look → delete it from the Saved tab → return to the still-mounted scan-results page → bookmark state correct.
5. Barber list → photo shows where `profile_image` exists, initials otherwise.
6. Barber list → ⓘ icon (not "View") → dialog shows photo, rating count, recent comments.
7. Time slots → line reads **"Best today:"** when the forecast card says "today" (not an ISO date).
8. Pick a date 8+ days out → weather box disappears cleanly, no crash.

---

## 2. Two things that will bite immediately

**`api/db.php` is deleted in the user's local working tree** (uncommitted). `git restore api/db.php` — nothing works without it.

**Two CLI scripts now exit 401** by design, because of `45b618b`: `scripts/run_admin_audit.php` and `scripts/run_admin_dashboard.php`. They include the endpoints directly with no session. Either give them a session or leave them broken; do not "fix" by removing the auth guard.

---

## 3. Local test environment (worked out, reuse it)

No Flutter/Dart. Available: PHP 8.4 (`pdo_pgsql`, `gd`, `curl`), PostgreSQL 16, Node 22, headless Chromium + Playwright at `/opt/node22/lib/node_modules/playwright`. Outbound egress to Render and Gemini is **blocked** by network policy.

Postgres refuses to run as root — run it as the `postgres` user, and put `PGDATA` outside the scratchpad (the scratchpad is `root`-only, so `postgres` cannot read it):

```bash
PGD=/var/tmp/pgtest; rm -rf $PGD; mkdir -p $PGD && chown postgres:postgres $PGD
su postgres -c "/usr/lib/postgresql/16/bin/initdb -D $PGD -U postgres --auth=trust -E UTF8"
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D $PGD -o '-h 127.0.0.1 -p 5433' -l $PGD/log start"
psql -h 127.0.0.1 -p 5433 -U postgres -c "CREATE DATABASE tatis;"
psql -h 127.0.0.1 -p 5433 -U postgres -d tatis -f database/schema.pg.sql   # loads clean, 25 tables
export DB_URL="postgresql://postgres@127.0.0.1:5433/tatis"
php -S 127.0.0.1:8090 -t api        # DB_URL must be exported in the server's env
```

`staff_users.role` is CHECK-constrained to **`'Admin'` / `'Receptionist'`** (capitalised). `require_admin` lowercases before comparing, so that is fine — but an insert with `'admin'` fails.

To mint a session token: insert a `staff_users` row, then call `issue_portal_session($pdo, $staffId)` from `api/admin_auth.php`. Send it as `Authorization: Bearer <token>` or `X-Portal-Token: <token>`.

For admin-web UI checks: `npx http-server -p 8098 -s .` from `web-admin/`, then drive with Playwright. Use a viewport **≥1240px** or `.split` collapses to one column and layout assertions become meaningless.

To unit-test PHP helpers without the request handler (which needs a live DB at include time), extract functions by brace-matching — a working extractor was used for the Top-3 tests; rewrite it in ~20 lines if needed.

---

## 4. What is left, in agreed order

Decisions already taken — do not re-litigate:

- Queue merge: barbers + queue **view** merge; **both price tiers stay** (walk-in ₱100 / appointment ₱500); read-side filters only, instantly reversible.
- Haircut catalog: DB-driven, gated on all 3 overlay PNGs existing.
- Kiosk payment: counter vs GCash recorded as **intent only**, no gateway call at the kiosk.
- Kiosk consent: per-use gate, reuse existing T&C copy.
- Recent activity: a real multi-type feed.
- Audit: money + bookings + staff accounts; **all actors including system/webhook**.
- Tipping: assessment only, not built.

### B3 — Audit logs (next up, the big one)

`audit_logs` schema at `database/schema.pg.sql:438-451`. Writer `audit_log()` at `api/db.php:232`. Reader `api/admin_audit.php`.

**Schema first.** One actor column, `user_id BIGINT` nullable, no FK — currently written with values from three incompatible identity spaces. Staff are `staff_users.staff_id`, barbers are `barbers.barber_id`; putting either in `user_id` collides with a customer id. Add via the codebase's `ADD COLUMN IF NOT EXISTS` habit:
`actor_type VARCHAR(20)` (`customer`/`staff`/`admin`/`barber`/`system`/`webhook`), `actor_id BIGINT` null, `actor_label VARCHAR(120)`.

**The reader throws away everything.** `admin_audit.php:67-81` selects `old_values`, `new_values`, `user_id`, `ip_address`, `user_agent` and flattens every row to title/description/time. **Extend it or none of the new detail is visible.** Also: hard cap 200 rows, no pagination, no server-side filter.

**Today: 25 call sites in 4 files** — `admin_users.php` ×15 (all pass `user_id = null`), `operating_schedule.php` ×5, `payments.php` ×3, `booking.php` ×2. Zero in `receptionist.php`, `payment_recording.php`, `paymongo/*`, `admin_hairstyles.php`, `admin_services.php`.

Sites to add, highest value first:

| Where | Anchor | Why |
|---|---|---|
| `completeRefund` | `receptionist.php:298`, after UPDATE at `:327` | Human marks money handed over; only record is free-text `completed_by` taken straight from client input (`:323`) |
| `confirmGatewayPayment` | `payments.php:373`, after `finalize_paid_intent` at `:447` | **The real capture path is unaudited** — the only captured-payment log (`:606`) is on the *mock* branch |
| `record_completion_payment` | `payment_recording.php:153` | All cash revenue enters here, invisible. Silent magic-number fallbacks `$amount = 500.0` (`:173`) and `100.0` (`:211`) when the total computes to 0 — audit the amount actually written |
| Refund row insert | `booking.php:1232-1246` | Cancel is audited, the refund it creates is not |
| `reschedule` | `booking.php:1311`, between `:1558` and commit at `:1570` | Unaudited; record old→new date/time and `reschedule_count` |
| `updateWalkinStatus` / `createWalkin` | `receptionist.php:484`, `:541` | Unaudited; `Completed` triggers payment recording at `:531` |
| `sync_payment_row` | `paymongo/webhook.php:210`, after `:243` and `:256` | **Blocker:** webhook.php does not require `db.php`, so `audit_log()` is not in scope and it builds its own PDO from env. Add the require first |

**Two existing bugs to fix while in here:**
- `capturePayment` shares a branch with `createIntent` (`payments.php:264`) and is therefore **logged as `CREATE_INTENT`** — wrong action type on a real money event.
- `audit_log()` swallows every `PDOException` and returns false (`db.php:253-255`), so a bad column fails silently. And `':record_id' => (string)$record_id` turns null into `''`, so `record_id` is never actually NULL.

Now that `45b618b` has landed, `require_admin($pdo)` returns the admin identity — thread it into the 15 `admin_users.php` calls **as `actor_type='admin'`, `actor_id=staff_id`**, never into `user_id`.

`scripts/test_audit_logging.php` bypasses `audit_log()` entirely (raw SQL), has no cleanup, and leaves 2 junk rows per run. Rewrite it to call the writer.

### B4 — Recent activity feed

`api/admin_dashboard.php:26-34` runs one query against `appointments` and stamps every row with the literal `'New appointment created'` (`:36-43`). It never reads the audit log. The client (`web-admin/admin/app.js:429-519`) already buckets into appointments/users/services/system and the filter offers all four — three can never match because the title is a constant.

Build from `audit_logs` after B3, union'd with `payments.paid_at`, `walkin_queue`, `appointment_refunds.created_at`, `barber_feedback` for pre-existing history. Emit `category` from the server rather than keyword-guessing on the client. Keep the 5-per-page pagination (`app.js:37`).

### B5 — DB-driven haircut catalog

Replace hardcoded `overlay_library_code_keys()` (`api/hairstyle_overlay_paths.php:27-55`).

**The gate predicate already exists and is correct**: `hairstyle_overlay_files_exist()` (`api/admin_hairstyles.php:364-386`) requires all three paths, checks disk then Supabase. Used only as a display flag (`:72`, `:109`), never in the customer path. Move it to `hairstyle_overlay_paths.php` so `variant_ranking.php` and `haircuts.php` can reach it.

**Fuzzy-matcher trap.** `resolve_hairstyle_overlay_key()` (`:219-243`) falls back to bidirectional `str_contains`, so a shorter new name is captured by a longer existing key — "Mid Fade" resolves to `curly mid fade` and inherits the curly artwork. Needs an exact-match guard once names come from the DB.

**Thin-texture cliff.** `filter_recommendations_for_customer()` (`api/variant_ranking.php:89`) returns the strict set only when `count >= 8`. Straight yields **exactly 8**. Deactivate one straight style and the guard flips and the fallback (`:93-95`) dumps all 24 styles — curly and wavy included — on a straight-haired customer.

### B6 — Queue merge toggle

`buildTracking()` (`web-admin/receptionist/app.js:580-716`) already normalises both queues into one shape. `barber_channel_filter_sql()` (`api/barber_channel.php:52-60`) is a single choke point covering ~10 sites. `system_settings` (`api/admin_settings.php:10-23`) is a ready key/value store with a toggle pattern to copy. Hardcoded inline `AND barber_channel = '...'` at `booking.php:410`, `kiosk.php:164`, `receptionist.php:143/562/614`, `slot_recommendation.php:718` each need handling separately.

### B7 — Kiosk (Flutter, unverifiable here)

The kiosk is **not** a separate app — `kiosk/` is a thin wrapper; all UI lives in `mobile-app/lib/kiosk/`.

- Consent: hang off `_startWalkIn()` (`mobile-app/lib/kiosk/kiosk_home_page.dart:56-61`). Reuse `mobile-app/lib/user/terms_and_conditions_page.dart`, which already has a kiosk clause at `:77-81`. Persist on `walkin_queue` — nothing exists in the DB until `createWalkin` fires at the end. There is **no idle timeout anywhere**; a kiosk left mid-flow stays mid-flow.
- Payment mode: insert between barber selection and `_joinQueue()` (`kiosk_barber_page.dart:90-143`). `record_completion_payment` hardcodes `'Cash'`; `'Digital'` is already allowed by the CHECK constraint.

---

## 5. Haircut library facts (already established)

**30 styles** across the three textures — **10 Straight, 10 Wavy, 10 Curly** (28 / 29 / 29 variants).

After the texture filter (`variant_matches_customer_texture`, `api/variant_ranking.php`): each customer sees **only their own texture** — straight → 10, wavy → 10, curly → 10, with no foreign variants in any pool. Wavy and curly used to be treated as interchangeable, so a wavy customer was shown all 16 wavy *and* curly styles; that pairing is gone, and `scripts/catalog_checks.php` now asserts both the separation and that no pool falls below 4 styles. The regex markers further down the function only apply to variants with no `hair_texture` value at all — the column decides everything else.

**Four styles exist in SQL but were never wired up** (`database/migrations/hairstyle_categories_and_catalog.sql:56-97`): Mid Fade, Curly Low Fade, Curly Fringe, Curly Undercut. Absent from `overlay_library_code_keys()`, no artwork on disk — invisible. Two of them collide with the fuzzy matcher.

**Adding a haircut needs images?** Not today — `create` validates only `styleName` (`api/admin_hairstyles.php:129-131`) and writes no variant row, so it can never be recommended (ranking INNER JOINs `hairstyle_variants`). After B5 the three PNGs become the real gate.

Suggested additions to reach 10/10/10, each checked against the fuzzy matcher:

- Straight (+2): `HC-SLICK-BACK` / Slick Back / `slick_back`; `HC-SIDE-PART` / Side Part / `side_part`
- Curly (+4): `HC-CURLY-HIGH-TOP` / Curly High Top / `curly_high_top`; `HC-CURLY-SHAG` / Curly Shag / `curly_shag`; `HC-AFRO-TAPER` / Afro Taper / `afro_taper`; `HC-COILY-SPONGE` / Coily Sponge Cut / `coily_sponge`

**Names to avoid** — each is swallowed by `str_contains` and would inherit another style's artwork: *Taper Fade*, *Mid Fade*, *Low Fade* (for a curly variant), *Burst Fade*, *Drop Fade*, *Fringe*, *Crew Cut*.

Artwork: `mobile-app/assets/images/overlays/<slug>/<slug>_{front,left,right}.png`, PNG only, 5 MB max (`admin_hairstyles.php:407-414`). There is no true back view — the `back` slot points at `_right.png`.

Adding one style end-to-end currently touches: `overlay_library_code_keys()`, `hairstyle_overlay_paths()`, `mobile-app/lib/user/scanner/overlay_registry.dart`, the seed `$catalog`, the 3 PNGs, and `pubspec.yaml` (folders are declared individually). B5 should collapse most of that.

---

## 6. Known issues found but NOT fixed

- `admin_hairstyles.php` overlay upload accepts an unknown `view`, writes the file, then **silently skips the DB update** (`:471-476`).
- Overlay upload updates `front_view_url`/`side_view_url`/`back_view_url` for **all variants of a style at once**, with no face-shape scoping (`:486-491`).
- `recommendWithInsights` falls back to rule-based only when Gemini returns unparseable JSON or empty topPicks — no timeout guard.
- `variant_ranking.php:208` sets `$sqlLimit = max(64, catalogSize * 3)` = 72, exactly the number of library variant rows. A style with a 4th variant silently truncates the result set.
- Weather: slot scoring thresholds are rain ≥60% and temp ≥33°C. At Philippine typical (31°C) neither fires and the tie-break is "closest to noon" — which is why 1 PM gets recommended on a hot day. Worth lowering the heat threshold (~30°C) and changing the neutral tie-break to prefer morning/late afternoon. **Not a bug, a tuning call — ask the user first.**
- `admin_audit.php` CSV export exports all loaded rows, not the filtered view, despite the button saying "Export view as CSV" (`app.js:3034-3040`).
