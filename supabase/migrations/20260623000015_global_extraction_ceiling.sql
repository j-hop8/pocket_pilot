-- Feature — App-wide daily ceiling for anonymous (demo) Gemini receipt scans.
--
-- The per-user 30/day cap (extraction_usage + check_extraction_quota) already
-- isolates each account, but demo mode mints a fresh anonymous account per
-- visitor, so total Gemini spend would scale with visitor count. This table
-- holds a single counter per day that ONLY anonymous callers count against; the
-- extract-receipt Edge Function checks/increments it with the service role
-- (which bypasses RLS). It is deliberately NOT reachable by client roles so it
-- can't be inflated directly — RLS is enabled with no policies and the table
-- privileges are revoked from anon/authenticated. Day boundary matches the
-- per-user functions (Asia/Taipei), set by the Edge Function.
--
-- Additive + idempotent: safe on `db push` and `db reset`.

CREATE TABLE IF NOT EXISTS public.global_extraction_usage (
  usage_date DATE PRIMARY KEY,
  count      INT  NOT NULL DEFAULT 0
);

-- RLS on + no policies → anon/authenticated get zero rows; service_role bypasses.
ALTER TABLE public.global_extraction_usage ENABLE ROW LEVEL SECURITY;

-- Defense-in-depth: also strip table-level privileges from client roles.
REVOKE ALL ON public.global_extraction_usage FROM anon, authenticated;

-- Atomic increment for one global slot on the given day, returning the new count.
-- Called only by the Edge Function (service role) AFTER a successful extraction,
-- so a failed scan never burns a slot. EXECUTE is granted to service_role only —
-- clients can't reach it, mirroring the read path (a service-role SELECT).
CREATE OR REPLACE FUNCTION public.record_global_extraction(p_day DATE)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  INSERT INTO global_extraction_usage (usage_date, count)
  VALUES (p_day, 1)
  ON CONFLICT (usage_date)
    DO UPDATE SET count = global_extraction_usage.count + 1
  RETURNING count INTO v_count;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.record_global_extraction(DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_global_extraction(DATE) TO service_role;
