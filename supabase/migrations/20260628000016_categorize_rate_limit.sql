-- Feature — Per-user daily quota for the Gemini auto-categorizer (categorize).
-- The categorize Edge Function batches a user's uncategorized merchant/item names
-- into one Gemini call (real money/quota), so cap each user's batches per day.
-- Kept independent of the extract-receipt budget (extraction_usage) so a big
-- categorize sweep doesn't eat the user's OCR allowance. Reserve-then-refund so a
-- failure doesn't burn quota AND concurrent batches can't overshoot the cap: the
-- function atomically reserves a slot before the Gemini call (rejecting the
-- over-limit request with 429), and the caller refunds the slot if the call fails.
-- Additive + idempotent: safe on `db push` and `db reset`.

-- ── 1. The daily counter table ───────────────────────────────────────────────
-- One row per user per (Asia/Taipei) calendar day. RLS lets a user read only
-- their own usage; all writes go through the SECURITY DEFINER function below.
CREATE TABLE IF NOT EXISTS categorize_usage (
  user_id    UUID    NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  usage_date DATE    NOT NULL,
  count      INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, usage_date)
);

ALTER TABLE categorize_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own categorize_usage" ON categorize_usage;
CREATE POLICY "own categorize_usage" ON categorize_usage
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Drop the earlier check-then-record functions if a prior version of this
-- migration created them, so a re-`db push` converges to the reserve/refund pair.
DROP FUNCTION IF EXISTS public.check_categorize_quota(INT);
DROP FUNCTION IF EXISTS public.record_categorize();

-- ── 2. Atomically reserve one categorize slot ────────────────────────────────
-- Takes one slot for today IF the caller is under p_limit, in a SINGLE row-locked
-- statement, so concurrent batches can't both pass a read-only check and overshoot
-- the cap (the bug a separate check-then-record had). Returns TRUE when a slot was
-- taken (caller may proceed to Gemini), FALSE when already at the limit. On a
-- failed Gemini call the caller gives the slot back via refund_categorize, so a
-- failure still doesn't burn quota. SECURITY DEFINER, scoped to auth.uid(); day
-- boundary Asia/Taipei, matching the extract-receipt quota.
CREATE OR REPLACE FUNCTION public.reserve_categorize(p_limit INT DEFAULT 20)
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

  -- First insert of the day starts at 1; otherwise increment only while under the
  -- limit. When the WHERE excludes the conflict row (at/over limit) the statement
  -- touches no row and RETURNING yields nothing, so v_count stays NULL.
  INSERT INTO categorize_usage (user_id, usage_date, count)
  VALUES (v_uid, v_today, 1)
  ON CONFLICT (user_id, usage_date)
    DO UPDATE SET count = categorize_usage.count + 1
    WHERE categorize_usage.count < p_limit
  RETURNING count INTO v_count;

  RETURN v_count IS NOT NULL;  -- true = a slot was reserved
END;
$$;

-- ── 3. Refund a reserved slot after a failed batch ───────────────────────────
-- Gives back the slot reserved above when the Gemini call ultimately fails, so a
-- failure doesn't permanently consume quota. Floored at 0; no-op when there's no
-- row for today. Single row-locked statement.
CREATE OR REPLACE FUNCTION public.refund_categorize()
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

  UPDATE categorize_usage
     SET count = GREATEST(count - 1, 0)
   WHERE user_id = v_uid AND usage_date = v_today
  RETURNING count INTO v_count;

  RETURN COALESCE(v_count, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_categorize(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reserve_categorize(INT) TO authenticated;
REVOKE ALL ON FUNCTION public.refund_categorize() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refund_categorize() TO authenticated;
