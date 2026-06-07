-- Feature — Remove saved carrier credentials.
-- Lets a user fully erase the personal info they stored for carrier sync: the
-- portal password (Vault secret) is deleted, the phone is cleared, and auto-sync
-- is turned off. Additive + idempotent: safe on `db push` and `db reset`.

-- Write-only credential eraser. SECURITY DEFINER runs as the function owner
-- (postgres) so it can delete from Vault; it scopes everything to the JWT's
-- auth.uid(). No-op when no credentials are stored.
CREATE OR REPLACE FUNCTION public.clear_carrier_credentials()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id  UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT password_secret_id INTO v_id
    FROM carrier_config WHERE user_id = v_uid;

  -- Drop the encrypted Vault secret if one exists.
  IF v_id IS NOT NULL THEN
    DELETE FROM vault.secrets WHERE id = v_id;
  END IF;

  -- Clear the stored login and stop auto-sync; keep the row (and its last-sync
  -- history) so the screen can still show "not connected" cleanly.
  UPDATE carrier_config
     SET phone              = NULL,
         password_secret_id = NULL,
         auto_sync_enabled  = FALSE,
         updated_at         = NOW()
   WHERE user_id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.clear_carrier_credentials() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clear_carrier_credentials() TO authenticated;
