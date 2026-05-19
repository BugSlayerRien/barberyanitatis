PayMongo integration (backend)
=================================

Environment variables
- `PAYMONGO_SECRET` - your PayMongo secret key (test or live). Required.
- `PAYMONGO_WEBHOOK_SECRET` - webhook signing secret used to validate incoming events. Optional but recommended.
- `PAYMONGO_API_URL` - optional override for API base URL (default: `https://api.paymongo.com/v1`).
- `PAYMONGO_SUCCESS_URL`, `PAYMONGO_FAILED_URL` - redirect URLs for hosted wallet checkout (`gcash`, `grab_pay`) when client does not provide them.
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS`, `DB_SSLMODE` - used by the webhook handler to update orders in PostgreSQL / Supabase.

Files
- `paymongo_client.php` - small HTTP client wrapper that reads `PAYMONGO_SECRET` and calls PayMongo API.
- `create-payment.php` - creates either:
  - payment intent flow (`card` and compatible methods), or
  - redirect source flow (`gcash`, `grab_pay`) and returns `checkout_url`.
- `payment-status.php` - GET `?intent_id=...&resource_type=payment_intent|source` to retrieve status for both flows.
- `webhook.php` - receives PayMongo webhooks, verifies signatures, updates PostgreSQL/Supabase orders, and handles `source.chargeable` by attempting a `/payments` charge from source.
- `schema-dry-run.php` - read-only diagnostics endpoint that inspects PostgreSQL/Supabase tables (`appointment_payment_intents`, `orders`, `payment_events`) and reports detected columns used by the webhook mapping logic.

Quick curl examples

Create payment intent (server-side):
```bash
curl -X POST https://your-server/backend/paymongo/create-payment.php \
  -H "Content-Type: application/json" \
  -d '{"amount":10000,"currency":"PHP","method":"gcash","description":"Appointment #123","appointment_id":"123","success_url":"https://your-app/success","failed_url":"https://your-app/failed"}'
```

Check payment status:
```bash
curl "https://your-server/backend/paymongo/payment-status.php?intent_id=pi_abc123&resource_type=payment_intent"
curl "https://your-server/backend/paymongo/payment-status.php?intent_id=src_abc123&resource_type=source"
```

Verify PostgreSQL/Supabase schema mapping (read-only):
```bash
curl "https://your-server/backend/paymongo/schema-dry-run.php"
```

Webhook setup
- Configure PayMongo webhook to point to `https://your-server/backend/paymongo/webhook.php`.
- Set the signing secret in `PAYMONGO_WEBHOOK_SECRET` on your server.
- Verify PayMongo signature format for your environment. The current verifier accepts:
  - raw HMAC SHA256 of request body in signature header, and
  - structured header format with `t=...` and `v1=...` (verifies against `hash_hmac('sha256', "$t.$payload", secret)`).

Notes
- Do NOT store secret keys in source code. Use environment variables or your host's secrets store.
- The webhook is PostgreSQL/Supabase-first and introspects available `orders` columns from `information_schema` to reduce schema coupling.
- If `payment_events` exists, webhook logs reconciliation entries there using available columns.
