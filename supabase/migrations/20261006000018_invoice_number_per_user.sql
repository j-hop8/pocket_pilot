-- invoice_number was globally UNIQUE (20260530000001_init), but invoices became
-- per-user in 20260531000005_auth_per_user. Every dedup check only sees the
-- caller's own rows (RLS on the client, `.eq("user_id", …)` in carrier ingest),
-- so an invoice already held by ANOTHER account — e.g. the same receipt scanned
-- in an earlier demo session — passed dedup and then failed the insert with
-- 23505 `invoices_invoice_number_key`. Scope the uniqueness to the owner.
-- NULLs stay distinct, so OCR receipts without a number are unaffected.
-- Idempotent — safe on `db push` and `db reset`.

ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_invoice_number_key;

CREATE UNIQUE INDEX IF NOT EXISTS invoices_user_invoice_number_key
  ON invoices(user_id, invoice_number);
