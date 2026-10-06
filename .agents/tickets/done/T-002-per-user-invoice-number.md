# T-002: Make invoice_number unique per user, not globally

**Goal:** Stop e-invoice scans (and carrier sync) failing with
`duplicate key value violates unique constraint "invoices_invoice_number_key"`
when the same invoice already exists in a *different* account.

**Background:** `invoices.invoice_number` has been globally `UNIQUE` since the init
migration, but rows became per-user in 0005 (RLS). Dedup checks only see the
caller's own rows (RLS on the client, `.eq("user_id", …)` on the server), so an
invoice held by another account passes dedup and then the insert hits 23505.
Repro on prod 2026-10-06: fresh demo account → import the BP61934238 fixture →
failed row with the 23505 error; a never-seen invoice number saves fine.

**Files in scope:** `supabase/migrations/20261006000018_invoice_number_per_user.sql` (new),
doc comments in `lib/data/invoice_repository.dart`,
`lib/features/scan/einvoice_qr_service.dart`, `lib/features/scan/receipt_ocr_service.dart`,
this ticket.

**Do NOT touch:** scan decode pipeline, server/edge ingest logic (already per-user).

**Acceptance criteria:**
- [x] Global `invoices_invoice_number_key` dropped; `UNIQUE (user_id, invoice_number)` added
- [x] Migration is idempotent (safe on `db push` and `db reset`)
- [x] After `supabase db push`: re-importing BP61934238 into a fresh demo account saves

**Verify:** `flutter analyze && flutter test`

**Owner:** claude
