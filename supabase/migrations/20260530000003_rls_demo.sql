-- DEMO-ONLY row-level security.
-- Phase 1 has no auth (spec: multi-user/auth out of scope), so the public anon
-- role is granted full access. This means anyone with the anon key can read/write
-- all data. Replace these blanket policies with per-user (auth.uid()) policies
-- when authentication is introduced post-demo.

ALTER TABLE categories     ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices       ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_items  ENABLE ROW LEVEL SECURITY;
ALTER TABLE carrier_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "demo all access" ON categories
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "demo all access" ON invoices
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "demo all access" ON invoice_items
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "demo all access" ON carrier_config
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
