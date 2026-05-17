# Authentication System Fix & Account Handling Guide

## Problem Explained

The app was split between **two authentication systems**:

1. **`public.users`** (app data table) — your custom user profile table
2. **`auth.users`** (Supabase Auth) — secure authentication credentials managed by Supabase

The issue: demo accounts were seeded only in `public.users`, but the app uses `auth.users` for sign-in. This created a mismatch.

### Why Two Tables?

- **`auth.users`**: Managed by Supabase. Handles passwords, email confirmation, OAuth tokens, recovery codes. Cannot be accessed directly (uses Supabase Auth API).
- **`public.users`**: Your app's domain table. Stores user profiles, roles, preferences, linked to bookings/favorites. Access via regular SQL/API.

This separation is standard: Auth handles security; your app table handles business logic.

---

## What Was Fixed

### 1. **Email Confirmation Error**
**Problem**: After signup, users got "Email not confirmed" when trying to login.  
**Solution**: 
- Supabase now auto-confirms emails on signup for development (safe for local testing).
- In production, you'd set up email sending; users would confirm via an email link.

### 2. **Signup Creates Both Records**
**Problem**: Signup created `auth.users` but not `public.users`, breaking profile lookups.  
**Solution**: 
- After successful signup, the app calls `api/auth_sync.php` to create a matching `public.users` record.
- This ensures every signed-in user has both an auth account and a profile record.

### 3. **Duplicate Email Prevention**
**Problem**: Users could sign up with the same email multiple times.  
**Solution**: 
- Before signup, the app checks if the email already exists (via new `checkEmailExists` action).
- Shows clear message: "This email is already registered. Try signing in instead."

### 4. **Input Validation & Format Hints**
**Problem**: Users didn't know what format to use for email or phone.  
**Solution**: 
- Email field now shows hint: `Format: yourname@example.com`
- Phone field now shows hint: `PH format: 09123456789 or 02-1234567`
- Philippine phone validation: accepts 09xx (11 digits), +639xx (12 digits), or landlines 2-8 (8-10 digits).

---

## Files Modified

### `mobile-app/lib/user/auth_page.dart`
- Updated `_register()` to:
  - Check for duplicate emails before signup
  - Add validation hints to email and phone fields
  - Sync signup to both `auth.users` and `public.users` via `auth_sync.php`
- Updated `_isValidPhone()` for Philippine format validation
- Updated `_fieldDecoration()` to support helper text with format hints

### `api/auth.php`
- Added `checkEmailExists` action to query if an email is already in use

### `api/auth_sync.php` (NEW)
- Server utility to sync Supabase Auth users to `public.users`
- Callable via HTTP POST or PHP function
- Creates a matching profile record after signup

---

## How Sign-Up Flow Works Now

```
1. User fills form (first name, last name, email, phone, password)
   ↓
2. App validates:
   - Required fields present
   - Email format valid (yourname@example.com)
   - Password >= 6 chars
   - Passwords match
   - Phone format valid (if provided)
   - Email not already registered
   ↓
3. App calls Supabase: signUp(email, password, metadata)
   → Supabase creates auth.users entry
   → Email is auto-confirmed (dev mode)
   → User is signed in immediately
   ↓
4. App syncs to public.users:
   POST api/auth_sync.php { email, full_name }
   → Creates public.users record with profile data
   → Placeholder password hash (auth happens via Supabase)
   ↓
5. User is signed in and navigated to dashboard
```

---

## How Sign-In Flow Works

```
1. User enters email & password
   ↓
2. App calls Supabase: signInWithPassword(email, password)
   → Supabase validates against auth.users
   → If email confirmed, returns session token
   ↓
3. App syncs profile:
   Query public.users WHERE email = user.email
   → Gets user_id, full_name, roles
   → Updates UserSession
   ↓
4. User navigated to dashboard based on role
```

---

## Provisioning Demo Accounts

If you seeded `public.users` manually and want to log in with those accounts, you need to provision them in Supabase Auth too.

### Quick Setup (One-time)

```powershell
# Set environment variables
$env:SUPABASE_URL = 'https://sergfnujsutcschocuuz.supabase.co'
$env:SUPABASE_SERVICE_ROLE = '<your-service-role-key>'

# Run provisioning script
php scripts/provision_auth_users.php
```

### Built-in Demo Accounts
The provisioning script knows these passwords:
- `admin@tatis.local` → `Admin123!`
- `receptionist@tatis.local` → `Reception123!`
- `barber@tatis.local` → `Barber123!`
- `customer@tatis.local` → `Customer123!`

### Dry Run (Preview)
```powershell
php scripts/provision_auth_users.php --dry-run
```

---

## Validations Added

### Email
- Must be valid format: `name@domain.com`
- Must not already be registered
- Case-insensitive duplicate check

### Password
- Minimum 6 characters
- Must match confirmation field
- Stored securely via Supabase Auth (never in PHP)

### Phone (Optional)
- If provided, must be valid Philippine format:
  - **Mobile**: `09XXXXXXXXX` (11 digits) or `+639XXXXXXXXX`
  - **Landline**: `0X-XXXXXXX` to `0XX-XXXXXX` (8-10 digits, area codes 2-8)
  - **Examples**: `09123456789`, `02-1234567`, `+639123456789`

### Name
- First and last name required, trimmed
- Combined for full name in profile and auth metadata

---

## Production Notes

### Email Confirmation
Currently disabled for development. For production:

1. Enable email sending in Supabase Auth settings
2. Users will receive a confirmation email on signup
3. App will show: "Check your email to confirm your account"
4. Update signup flow to handle `session == null` (email confirmation required)

### Service Role Key Security
The provisioning script requires `SUPABASE_SERVICE_ROLE`. This is sensitive:
- Never commit to git (already in `.gitignore`)
- Only pass via environment variables or secure vaults
- Rotate periodically in production

### Row Level Security (RLS)
The `public.users` table uses RLS (Row Level Security):
- Users can only see/edit their own profiles
- Auth users must be confirmed to trigger RLS policies
- Admin roles bypass RLS via service role key

---

## Testing Sign-Up

1. Start the app
2. Go to "Sign up" tab
3. Fill form (use test email, PH phone)
4. Click "Create Account"
5. App should navigate to dashboard automatically
6. Try logging out, then sign in with the new account

---

## Troubleshooting

### "Email not confirmed" error
- Supabase Auth has email confirmation enabled
- For dev: run provisioning script or update `.env` to disable email confirmation
- For prod: set up email sending in Supabase dashboard

### "This email is already registered"
- Email exists in `public.users` or `auth.users`
- Use a different email or try signing in if you have the password

### "Invalid Philippine phone number"
- Format not recognized; check hint text in signup form
- Valid: `09123456789`, `02-1234567`, `+639123456789`

### Phone not saved after signup
- Phone field is optional; if left empty, no error
- When provided, must match PH format or signup fails

---

## File Locations

- Sign-up flow: [`mobile-app/lib/user/auth_page.dart`](../../mobile-app/lib/user/auth_page.dart) (lines 362+)
- Auth endpoints: [`api/auth.php`](../auth.php) and [`api/auth_sync.php`](../auth_sync.php)
- Provisioning script: [`scripts/provision_auth_users.php`](../provision_auth_users.php)
- Environment: [`.env`](../../.env) (keep local, not in git)
