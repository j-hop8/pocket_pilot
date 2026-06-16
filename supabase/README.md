# Supabase (PocketPilot)

Hosted Postgres + auto-generated API. The Flutter app talks to it directly via the
`supabase_flutter` Dart SDK — there is no custom backend in Phase 1.

## One-time setup

1. Create a free project at https://supabase.com → note the **Project URL**, **anon key**,
   the **project ref** (the `xxxx` in `xxxx.supabase.co`), and your **DB password**.
2. Install the CLI: see project plan (`brew install supabase/tap/supabase`, or the
   standalone binary). Then:
   ```sh
   supabase link --project-ref <ref>
   supabase db push        # applies everything in migrations/
   ```
   (`db push` connects to the remote DB directly — no Docker needed.)

## Migrations (apply in order)

| File | Purpose |
|---|---|
| `migrations/20260530000001_init.sql` | Core schema: categories, invoices, invoice_items, carrier_config + indexes (spec §4) |
| `migrations/20260530000002_seed_categories.sql` | Seed the 10-category v1 enum |
| `migrations/20260530000003_rls_demo.sql` | **Demo-only** RLS: anon role gets full access (no auth in Phase 1) |
| `migrations/20260531000004_carrier_sync.sql` | Feature 1: drop unused invoice tax-id columns; add carrier login credential columns |

After pushing, Supabase Studio should show 4 tables and 10 rows in `categories`.
Already pushed the earlier migrations to a live DB? Just `supabase db push` again —
the carrier-sync migration is additive (idempotent `ALTER`s), so no reset is needed.

## Carrier sync (Feature 1)

Invoices are imported in-app from the Ministry of Finance e-invoice carrier CSV
(消費明細 export): **Carrier sync** screen → *Choose CSV file*. Headers + line
items are stored with `source='carrier'`, deduped by `invoice_number`, and each
invoice gets an auto-assigned category. Carrier credentials entered on that
screen are saved to `carrier_config` for the future auto-sync path.

⚠️ **Credentials security:** under the demo RLS the anon role can read every
table, so the stored `password` is readable by anyone with the anon key — fine
for this local single-user demo only. Production should encrypt / use a
server-side secret, add per-user (`auth.uid()`) RLS, and prefer the official MOF
**E-Invoice API** (`carrierInvChk` / `carrierInvDetail`, mobile barcode +
verification code, run from a Supabase **Edge Function** so the AppID secret
stays server-side) over storing the portal password.

## Edge Functions

Server-side helpers the app invokes with the user's session JWT (`supabase.functions.invoke`):

| Function | Purpose |
|---|---|
| `merchant-lookup` | Resolves an 8-digit 統一編號 to a business name (GCIS/FIA proxy, no CORS in-browser). |
| `extract-receipt` | Reads a receipt/invoice **photo** with Google Gemini and returns the structured fields the Receipt tab auto-saves (`source='ocr'`). Keeps `GOOGLE_AI_API_KEY` server-side; capped at **30 extractions per user per day**. |

Deploy + configure the receipt scanner:

```sh
# Get an API key from https://aistudio.google.com/apikey
supabase secrets set GOOGLE_AI_API_KEY=<your-key>
supabase functions deploy extract-receipt
```

On a rate limit / overload (HTTP 429 or 503) the function automatically retries
the next model in a fallback chain — `gemini-3.1-flash-lite` → `gemma-3-12b-it` →
`gemma-3-4b-it` → `gemma-3-27b-it` → `gemini-2.5-flash` (see
`_shared/gemini_receipt.ts`). The `GOOGLE_AI_API_KEY` must have access to these
models; only after every model is rate-limited does a scan fail.

Because each call hits the paid Gemini API, the function enforces a **per-user
daily quota** (migration `..._extract_receipt_rate_limit.sql`, both RPCs run
under the caller's JWT). Before extracting it calls `check_extraction_quota(p_limit)`
(read-only) and answers **429 `{code:"rate_limited"}`** once the user is at the
limit — the app then shows "daily scan limit reached". Only *after* a successful
extraction does it call `record_extraction()`, which bumps an `extraction_usage`
row keyed by user + Asia/Taipei day; a failed scan (502) spends no slot. The
limit lives as `DAILY_LIMIT` in the function and the SQL default.

Local run: `supabase functions serve extract-receipt` (reads `GOOGLE_AI_API_KEY` from
`supabase/.env` / your shell). Smoke test with a base64 image:

```sh
# Use a signed-in user's access token, not the anon key — the quota counter
# needs auth.uid(), so the anon key answers 502 "not authenticated".
curl -s -X POST "$SUPABASE_URL/functions/v1/extract-receipt" \
  -H "Authorization: Bearer $USER_JWT" -H 'Content-Type: application/json' \
  -d "{\"image\":\"$(base64 -i receipt.jpg)\"}" | jq
```

## App config

The app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` at build time via
`--dart-define-from-file=dart_defines.json` (gitignored). See `dart_defines.example.json`
in the project root. The anon key is publishable; the Gemini key is **never** in the
app — it lives in the `extract-receipt` Edge Function secret (above).
