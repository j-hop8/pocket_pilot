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

After pushing, Supabase Studio should show 4 tables and 10 rows in `categories`.

## App config

The app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` at build time via
`--dart-define-from-file=dart_defines.json` (gitignored). See `dart_defines.example.json`
in the project root. The anon key is publishable; the Gemini key (Phase 3+) is **never**
in the app — it lives in an Edge Function secret.
