-- Auth + per-user data isolation.
-- Supersedes the Phase-1 demo RLS (20260530000003_rls_demo): once Google sign-in
-- is required, every row is owned by a Supabase auth user and visible only to
-- that user. Idempotent so it is safe on `db push` and `db reset`.

-- 1. Ownership columns. DEFAULT auth.uid() means inserts need no app changes:
--    the column self-fills from the JWT before the RLS WITH CHECK runs.
ALTER TABLE invoices       ADD COLUMN IF NOT EXISTS user_id UUID
  REFERENCES auth.users(id) ON DELETE CASCADE DEFAULT auth.uid();
ALTER TABLE invoice_items  ADD COLUMN IF NOT EXISTS user_id UUID
  REFERENCES auth.users(id) ON DELETE CASCADE DEFAULT auth.uid();
ALTER TABLE carrier_config ADD COLUMN IF NOT EXISTS user_id UUID
  REFERENCES auth.users(id) ON DELETE CASCADE DEFAULT auth.uid();

-- One carrier_config row per user (the app upserts on this conflict target).
CREATE UNIQUE INDEX IF NOT EXISTS carrier_config_user_id_key
  ON carrier_config(user_id);

CREATE INDEX IF NOT EXISTS idx_invoices_user      ON invoices(user_id);
CREATE INDEX IF NOT EXISTS idx_invoice_items_user ON invoice_items(user_id);

-- 2. Replace the blanket demo policies with per-user policies. Dropping the
--    demo policies (which granted the anon role) also removes anon access; RLS
--    denies by default, so no anon policy is recreated.
DROP POLICY IF EXISTS "demo all access" ON categories;
DROP POLICY IF EXISTS "demo all access" ON invoices;
DROP POLICY IF EXISTS "demo all access" ON invoice_items;
DROP POLICY IF EXISTS "demo all access" ON carrier_config;

-- Categories are shared reference data: any signed-in user may read them.
CREATE POLICY "categories readable" ON categories
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "own invoices" ON invoices
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "own invoice_items" ON invoice_items
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "own carrier_config" ON carrier_config
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- NOTE: rows created under the demo (user_id IS NULL) become invisible under
-- these policies. Run `supabase db reset` on the dev project for a clean slate
-- (it re-seeds categories).
