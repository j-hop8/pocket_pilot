-- Feature — Block demo (anonymous) accounts from storing carrier credentials.
--
-- Demo mode signs users in anonymously (supabase.auth.signInAnonymously). Those
-- throwaway accounts must not be able to save government e-invoice portal logins
-- into Vault — the app hides the UI, but the anon key is public, so guard the
-- SECURITY DEFINER setter itself. Anonymous sessions carry `is_anonymous: true`
-- in the JWT, readable here via auth.jwt(). Carrier sync is likewise rejected
-- for anonymous JWTs at the Node backend's /sync/now.
--
-- Re-declares set_carrier_credentials identically to
-- 20260606000006_carrier_auto_sync.sql, adding only the anonymous guard.
-- Additive + idempotent: safe on `db push` and `db reset`.

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

  -- Demo accounts (anonymous sign-in) can't store portal credentials.
  IF COALESCE((auth.jwt() ->> 'is_anonymous')::boolean, false) THEN
    RAISE EXCEPTION 'demo accounts cannot store carrier credentials';
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
