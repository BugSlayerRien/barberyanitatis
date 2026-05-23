# Tier 1 stability checklist

Use this before adding features. Each item should pass on **local XAMPP** with Apache + PostgreSQL running.

## A. Customer auth

- [ ] **Email sign-up** creates user in `public.users` and can sign in
- [ ] **Email sign-in** returns session; `UserSession.userId` set in Flutter
- [ ] **Google OAuth** (if enabled): same email always uses Google button (not email/password for Gmail-only accounts)
- [ ] No recurring **401** on `api/auth.php` after successful login

**Fail notes:** Check `.env`, Supabase keys in `main.dart`, `api/auth_sync.php` placeholder hash for OAuth users.

---

## B. Booking API (no 500s)

- [ ] `POST booking.php` `action: listByCustomer` with valid `userID` → **200** + `appointments` array
- [ ] `POST booking.php` `action: create` → **201** + `appointmentID`
- [ ] `POST time_slots.php` `action: availabilityByBarberMonth` → **200** + `availability`
- [ ] No `services_service_channel_check already exists` in response

**Quick test (PowerShell):**

```powershell
$base = "http://localhost/barberyanitatis/tatis_barbershop/api"
$body = '{"action":"listByCustomer","userID":1}'
Invoke-RestMethod -Uri "$base/booking.php" -Method POST -Body $body -ContentType "application/json"
```

---

## C. Payment → status sync

- [ ] After mock/gateway **Paid**, appointment shows **Scheduled** (not stuck on PendingPayment)
- [ ] Customer **Upcoming** tab loads without database error
- [ ] Paid row in `payments` or `appointment_payments` promotes status on list load

---

## D. Receptionist (web — primary desk)

Path: `web-admin/receptionist/`

- [ ] Dashboard loads; **Tracking** shows regular + exclusive queues
- [ ] **PENDING PAYMENT** card shows **Cancel** (and not only Complete)
- [ ] **Cancel** removes appointment / releases slot
- [ ] **Complete** works for in-service appointments
- [ ] Past slots auto-complete or disappear from tracking after refresh

---

## E. Barber

- [ ] **My schedule** calendar shows month grid + day appointments
- [ ] **Request day off** (future date only) → Pending on calendar
- [ ] Receptionist **Approve** on web → day blocked / reflected on barber calendar

---

## F. End-to-end scripts (manual)

### F1 — Book and pay

1. Customer: pick style → book → pay (mock if needed)
2. Appointments → **Upcoming** → Scheduled, Paid
3. Receptionist tracking: appears (or pending payment until paid)
4. Barber calendar: shows on correct date

### F2 — Cancel pending payment

1. Leave or create **PendingPayment** appointment
2. Receptionist → **Cancel**
3. Customer list: cancelled or gone from upcoming
4. Slot available again in calendar (if within 7-day window)

### F3 — Complete past slot

1. Appointment in the past still **Scheduled**
2. Open receptionist dashboard (automation runs)
3. Status **Completed**; leaves tracking

---

## G. Before production

- [ ] Remove `API_INSECURE_SSL` / `AI_SERVICE_INSECURE_SSL` dev flags
- [ ] Replace mock payment with real gateway (PayMongo) if going live
- [ ] Lock down admin/receptionist web with login
- [ ] Rotate API keys out of repo / use `.env` only

---

## Status log

| Date | Tester | A | B | C | D | E | F |
|------|--------|---|---|---|---|---|---|
|      |        |   |   |   |   |   |   |
