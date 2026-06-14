-- Feature — E-Invoice QR scan: restore buyer/seller tax IDs.
-- The carrier-sync migration (20260531000004) dropped seller_tax_id and
-- buyer_tax_id as "not useful for expense tracking". The QR-scan feature does
-- carry and store them (買方/賣方統一編號 are encoded in the e-invoice QR), so
-- inserts from the scan review screen failed with PGRST204 "could not find the
-- 'buyer_tax_id' column". Re-add them. Additive + idempotent: safe on both
-- `db push` and `db reset`.
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS seller_tax_id VARCHAR(8); -- 賣方統一編號
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS buyer_tax_id  VARCHAR(8); -- 買方統一編號
