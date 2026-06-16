-- Feature — Per-user daily quota for the Gemini receipt OCR (extract-receipt).
-- Every extract-receipt call hits the Google Gemini API (real money/quota), so
-- cap each user at 30 extractions per day. One counter row per (user, day); the
-- Edge Function calls consume_extraction_quota() before each Gemini call.
-- Additive + idempotent: safe on `db push` and `db reset`.
--
-- NOTE: success-only counting (check before / record after a successful scan)
-- supersedes consume_extraction_quota in migration
-- 20260616000013_extract_receipt_success_only_quota.sql. This file is kept as
-- originally applied to the remote; see that migration for the current behaviour.

-- ── 1. The daily counter table ───────────────────────────────────────────────
-- One row per user per (Asia/Taipei) calendar day. RLS lets a user read only
-- their own usage; all writes go through the SECURITY DEFINER function below.
CREATE TABLE IF NOT EXISTS extraction_usage (
  user_id    UUID    NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  usage_date DATE    NOT NULL,
  count      INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, usage_date)
);

ALTER TABLE extraction_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own extraction_usage" ON extraction_usage;
CREATE POLICY "own extraction_usage" ON extraction_usage
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ── 2. Atomic check-and-increment ────────────────────────────────────────────
-- Bumps today's counter and returns whether the caller is still within p_limit.
-- SECURITY DEFINER (runs as owner) so it can write the table regardless of RLS;
-- scopes everything to the JWT's auth.uid(), mirroring set_carrier_credentials.
-- The day boundary is Asia/Taipei (the app's audience), so "30/day" resets at
-- local midnight rather than UTC. The upsert is a single row-locked statement,
-- so concurrent calls can't both slip past the limit.
CREATE OR REPLACE FUNCTION public.consume_extraction_quota(p_limit INT DEFAULT 30)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_today DATE := (now() AT TIME ZONE 'Asia/Taipei')::date;
  v_count INT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  INSERT INTO extraction_usage (user_id, usage_date, count)
  VALUES (v_uid, v_today, 1)
  ON CONFLICT (user_id, usage_date)
    DO UPDATE SET count = extraction_usage.count + 1
  RETURNING count INTO v_count;

  RETURN v_count <= p_limit;  -- false once the (p_limit+1)-th call lands
END;
$$;

REVOKE ALL ON FUNCTION public.consume_extraction_quota(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_extraction_quota(INT) TO authenticated;
