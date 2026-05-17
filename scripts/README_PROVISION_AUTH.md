Provision Supabase Auth Users
=============================

This script helps provision demo users from the local `users` table into Supabase Auth using the Admin API.

Security: the script requires the Supabase "Service Role" key. Treat this key as highly sensitive. Do not commit it to source control.

Usage
-----

Set environment variables and run:

```bash
export SUPABASE_URL=https://<your-project>.supabase.co
export SUPABASE_SERVICE_ROLE=<your-service-role-key>
php scripts/provision_auth_users.php
```

Or pass args:

```bash
php scripts/provision_auth_users.php --supabase-url=https://... --service-role=KEY
```

Options
-------
- `--default-password` — password to use for users not in the built-in mapping
- `--dry-run` — show what would run without calling the Admin API

Notes
-----
- The script contains a mapping for seeded demo accounts (`admin@tatis.local`, `receptionist@tatis.local`, `barber@tatis.local`, `customer@tatis.local`) and will provision those with their known demo passwords.
- For other existing rows in the `users` table you must provide a plaintext password using `--default-password` or create the user manually in Supabase Auth.
- After provisioning, users should be able to sign in via the app (which uses Supabase Auth).
