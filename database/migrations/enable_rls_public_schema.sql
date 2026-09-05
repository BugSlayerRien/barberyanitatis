-- Enable Row Level Security on every table in the public schema.
--
-- WHY THIS IS SAFE FOR THIS APP
-- -----------------------------
-- Nothing in this system reads application tables through Supabase's PostgREST
-- layer:
--   * api/db.php connects directly to Postgres with DB_URL (a superuser/owner
--     role). Superusers and table owners BYPASS RLS, so the PHP API is
--     unaffected by these changes.
--   * The Flutter app uses Supabase ONLY for auth (Supabase.instance.client.auth).
--     It makes zero .from() / .rpc() table calls, so it never touches PostgREST.
--   * Supabase Storage is accessed server-side with the service_role key, which
--     also bypasses RLS.
--
-- What this actually closes: Supabase always exposes a public REST endpoint at
-- https://<project>.supabase.co/rest/v1/<table>. The anon key is embedded in the
-- shipped Flutter app and is therefore public. With RLS disabled, anyone holding
-- that key can read/write any table that has grants for anon/authenticated,
-- bypassing every business rule in the PHP API. Enabling RLS with no policies
-- makes the default DENY for those roles.
--
-- DELIBERATELY NOT USED: FORCE ROW LEVEL SECURITY. That would subject the table
-- OWNER to RLS as well, which would break the PHP API. Do not add it unless the
-- API is first moved to a dedicated non-owner role with explicit policies.
--
-- BEFORE RUNNING, confirm the API role really does bypass RLS:
--     SELECT current_user, usesuper FROM pg_user WHERE usename = current_user;
-- Run that using the DB_URL credentials. If usesuper is false AND the role does
-- not own the tables, STOP -- enabling RLS will break the API until policies
-- exist for that role.
--
-- Idempotent: safe to re-run. New tables added later are not covered
-- automatically -- re-run this after adding tables (several tables in this
-- project are created at runtime by ensure_*_table() helpers in api/).

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT c.relname AS table_name
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relkind = 'r'          -- ordinary tables only
          AND c.relrowsecurity = FALSE -- skip ones already enabled
        ORDER BY c.relname
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', r.table_name);
        RAISE NOTICE 'RLS enabled: public.%', r.table_name;
    END LOOP;
END
$$;

-- Defense in depth: remove any direct grants the anon/authenticated roles may
-- have picked up. With RLS on, these roles are denied by default anyway; this
-- also removes them from tables added before RLS existed.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
        REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        REVOKE ALL ON ALL TABLES IN SCHEMA public FROM authenticated;
        REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM authenticated;
    END IF;
END
$$;

-- Verify afterwards: every row should show rowsecurity = true.
--     SELECT tablename, rowsecurity
--     FROM pg_tables
--     WHERE schemaname = 'public'
--     ORDER BY rowsecurity, tablename;
--
-- And confirm the REST surface is closed (should return a permission/RLS error,
-- not data):
--     curl -s "https://<project>.supabase.co/rest/v1/users?select=*&limit=1" \
--          -H "apikey: <anon key>"
