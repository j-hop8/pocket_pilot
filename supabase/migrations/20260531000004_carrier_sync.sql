-- Feature 1 — E-Invoice Carrier Sync schema changes.
-- Forward (additive) migration: applies via `supabase db push` whether or not
-- the init schema was already pushed. Idempotent guards keep it safe on a fresh
-- `db reset` too.

-- Invoices: drop fields that are not useful for expense tracking. The carrier
-- CSV also exposes invoice status (發票狀態) and an allowance flag (折讓); those
-- are likewise not stored.
ALTER TABLE invoices DROP COLUMN IF EXISTS seller_tax_id; -- 賣方統一編號
ALTER TABLE invoices DROP COLUMN IF EXISTS buyer_tax_id;  -- 買方統編

-- carrier_config: persist the carrier login credentials entered in the in-app
-- Carrier settings screen (single-row config).
--
-- SECURITY: the Phase-1 demo RLS (rls_demo migration) grants the anon role full
-- access, so `password` here is readable by anyone holding the anon key —
-- acceptable only for this local single-user demo. Before any real deployment:
-- encrypt these / move them to a server-side secret, add per-user (auth.uid())
-- RLS, and prefer the barcode + verification-code API over storing the portal
-- password at all.
ALTER TABLE carrier_config ADD COLUMN IF NOT EXISTS phone                  TEXT;        -- 手機號碼
ALTER TABLE carrier_config ADD COLUMN IF NOT EXISTS password               TEXT;        -- 密碼
ALTER TABLE carrier_config ADD COLUMN IF NOT EXISTS card_verification_code TEXT;        -- 條碼驗證碼
ALTER TABLE carrier_config ADD COLUMN IF NOT EXISTS updated_at             TIMESTAMPTZ DEFAULT NOW();
