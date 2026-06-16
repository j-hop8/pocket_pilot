-- Feature — Success-only counting for the extract-receipt daily quota.
--
-- Supersedes consume_extraction_quota (migration
-- 20260615000012_extract_receipt_rate_limit.sql), which did one atomic
-- check-and-increment *before* the Gemini call — so a failed extraction still
-- spent a slot. The Edge Function now (1) checks the quota read-only with
-- check_extraction_quota() before calling Gemini (the 31st request is still
-- rejected with 429 before we spend any API money), and (2) records a slot with
-- record_extraction() only *after* a successful extraction. A failed scan no
-- longer counts against the user's 30/day.
--
-- Additive + idempotent: safe on `db push` and `db reset`. consume_extraction_quota
-- is intentionally left in place (now unused) so the previously-deployed Edge
-- Function keeps working until the new one is deployed; drop it in a later cleanup
-- migration once the new function is live everywhere.

-- ── Read-only quota check ─────────────────────────────────────────────────────
-- Returns whether the caller still has room for at least one more extraction
-- today, WITHOUT consuming a slot. SECURITY DEFINER (runs as owner) so it can read
-- the table regardless of RLS; scopes everything to the JWT's auth.uid(), mirroring
-- set_carrier_credentials. Day boundary is Asia/Taipei, so "30/day" resets at local
-- midnight rather than UTC.
CREATE OR REPLACE FUNCTION public.check_extraction_quota(p_limit INT DEFAULT 30)
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

  SELECT count INTO v_count
    FROM extraction_usage
   WHERE user_id = v_uid AND usage_date = v_today;

  RETURN COALESCE(v_count, 0) < p_limit;  -- true while there's room for one more
END;
$$;

-- ── Record one successful extraction ──────────────────────────────────────────
-- Bumps today's counter by one and returns the new count. Called only AFTER a
-- successful Gemini extraction, so failed scans don't burn a slot. The upsert is a
-- single row-locked statement.
CREATE OR REPLACE FUNCTION public.record_extraction()
RETURNS INT
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

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.check_extraction_quota(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_extraction_quota(INT) TO authenticated;
REVOKE ALL ON FUNCTION public.record_extraction() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_extraction() TO authenticated;
