-- Feature — Automatic E-Invoice Carrier Sync.
-- Adds the per-user sync settings + last-sync status, moves the portal password
-- into Supabase Vault (write-only from the client), and schedules the hourly
-- server-side sync. Additive + idempotent: safe on `db push` and `db reset`.

-- ── 1. carrier_config: sync settings + last-sync status ──────────────────────
ALTER TABLE carrier_config
  ADD COLUMN IF NOT EXISTS auto_sync_enabled     BOOLEAN     NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS sync_interval_minutes INTEGER     NOT NULL DEFAULT 60,  -- hourly
  ADD COLUMN IF NOT EXISTS last_sync_status      TEXT,        -- 'ok' | 'error' | 'running'
  ADD COLUMN IF NOT EXISTS last_sync_error       TEXT,
  ADD COLUMN IF NOT EXISTS last_sync_attempt_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS password_secret_id    UUID;        -- → vault.secrets.id

-- ── 2. Supabase Vault for the portal password ───────────────────────────────
-- The password is no longer kept as plaintext on the table; it lives encrypted
-- in Vault, readable only by the service role (the carrier-sync Edge Function).
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

ALTER TABLE carrier_config DROP COLUMN IF EXISTS password;  -- was Phase-1 plaintext

-- Defensive: the decrypted view must never be reachable by client roles.
DO $$
BEGIN
  REVOKE ALL ON vault.decrypted_secrets FROM anon, authenticated;
EXCEPTION WHEN undefined_table OR undefined_object THEN
  NULL; -- Vault not present in this environment
END $$;

-- Write-only credential setter. SECURITY DEFINER runs as the function owner
-- (postgres) so it can write Vault; it scopes everything to the JWT's auth.uid().
-- Pass p_password = NULL/'' to keep the current password ("leave blank").
CREATE OR REPLACE FUNCTION public.set_carrier_credentials(
  p_phone    TEXT,
  p_password TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, extensions
AS $$
DECLARE
  v_uid         UUID := auth.uid();
  v_secret_name TEXT;
  v_secret_id   UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  v_secret_name := 'carrier_pw_' || v_uid::text;

  -- Ensure the (single) config row exists and update the phone.
  INSERT INTO carrier_config (user_id, phone)
  VALUES (v_uid, NULLIF(btrim(p_phone), ''))
  ON CONFLICT (user_id) DO UPDATE
    SET phone = EXCLUDED.phone,
        updated_at = NOW();

  -- Only touch the password when one was supplied.
  IF p_password IS NOT NULL AND btrim(p_password) <> '' THEN
    SELECT id INTO v_secret_id FROM vault.secrets WHERE name = v_secret_name;
    IF v_secret_id IS NULL THEN
      v_secret_id := vault.create_secret(
        p_password, v_secret_name, 'PocketPilot carrier portal password');
    ELSE
      PERFORM vault.update_secret(v_secret_id, p_password);
    END IF;
    UPDATE carrier_config
       SET password_secret_id = v_secret_id, updated_at = NOW()
     WHERE user_id = v_uid;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_carrier_credentials(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_carrier_credentials(TEXT, TEXT) TO authenticated;

-- Server-side read-back for the carrier-sync Edge Function (service role only).
-- Returns the decrypted portal password for a user, or NULL if none is stored.
CREATE OR REPLACE FUNCTION public.get_carrier_secret(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, extensions
AS $$
DECLARE
  v_id     UUID;
  v_secret TEXT;
BEGIN
  SELECT password_secret_id INTO v_id
    FROM carrier_config WHERE user_id = p_user_id;
  IF v_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets WHERE id = v_id;
  RETURN v_secret;
END;
$$;

REVOKE ALL ON FUNCTION public.get_carrier_secret(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_carrier_secret(UUID) TO service_role;

-- ── 3. Hourly schedule (pg_cron → pg_net → Edge Function) ────────────────────
-- Best-effort: pg_cron/pg_net aren't in every local Postgres image, so failures
-- here are downgraded to notices and never break `db reset`.
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  CREATE EXTENSION IF NOT EXISTS pg_net;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron/pg_net unavailable, skipping (%).', SQLERRM;
END $$;

-- Recreate the schedule from two Vault secrets the operator sets once:
--   edge_carrier_sync_url         = https://<ref>.supabase.co/functions/v1/carrier-sync
--   edge_carrier_sync_cron_secret = matches the function's CRON_SECRET env
-- Re-runnable after the secrets are set: SELECT public.ensure_carrier_sync_schedule();
CREATE OR REPLACE FUNCTION public.ensure_carrier_sync_schedule()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, extensions
AS $$
DECLARE
  v_url    TEXT;
  v_secret TEXT;
BEGIN
  IF to_regnamespace('cron') IS NULL OR to_regnamespace('net') IS NULL THEN
    RETURN 'pg_cron/pg_net not enabled; schedule skipped';
  END IF;

  SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets WHERE name = 'edge_carrier_sync_url';
  SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets WHERE name = 'edge_carrier_sync_cron_secret';

  IF v_url IS NULL THEN
    RETURN 'edge_carrier_sync_url vault secret not set; schedule skipped';
  END IF;

  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'carrier-sync-hourly') THEN
    PERFORM cron.unschedule('carrier-sync-hourly');
  END IF;

  PERFORM cron.schedule(
    'carrier-sync-hourly',
    '0 * * * *',  -- top of every hour; the function honors each user's interval
    format($q$
      SELECT net.http_post(
        url     := %L,
        headers := jsonb_build_object(
                     'Content-Type', 'application/json',
                     'x-cron-secret', %L),
        body    := jsonb_build_object('mode', 'cron')
      );
    $q$, v_url, COALESCE(v_secret, ''))
  );
  RETURN 'carrier-sync-hourly scheduled';
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_carrier_sync_schedule() FROM PUBLIC;

-- Apply now (no-op locally / before secrets exist).
DO $$
BEGIN
  RAISE NOTICE '%', public.ensure_carrier_sync_schedule();
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ensure_carrier_sync_schedule failed: %', SQLERRM;
END $$;
