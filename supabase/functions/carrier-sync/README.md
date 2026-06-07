# carrier-sync Edge Function

Logs into the MOF e-invoice portal with a remote headless browser, downloads the
消費明細 CSV, and ingests new invoices for a user. Two trigger modes share one
ingestion path:

- **User "Sync now"** — the app calls `supabase.functions.invoke('carrier-sync')`
  with the user's JWT → syncs that single user.
- **Scheduled** — `pg_cron` POSTs hourly with an `x-cron-secret` header → syncs
  every user whose `auto_sync_enabled` is on and whose interval has elapsed.

## Why a remote browser?

A Supabase Edge Function (Deno) can't host a Chromium binary, so `scrape.ts`
drives a **remote** headless Chromium over CDP. Point `BROWSER_WS_ENDPOINT` at a
hosted browser (Browserbase / Browserless) or a self-hosted `browserless/chrome`.

> ⚠️ **Go/no-go:** the portal login (login_challenge / Ory Hydra) may present a
> CAPTCHA, a citizen certificate (自然人憑證), or 2FA — any of which defeats
> unattended scraping. The selectors in `scrape.ts` are best-effort and **must be
> confirmed against the live portal**. If login can't be automated, users fall
> back to the manual CSV import (still available in the app).

## Secrets / env

Auto-injected by the runtime: `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`. You must set:

| Name                  | Where                                   |
| --------------------- | --------------------------------------- |
| `BROWSER_WS_ENDPOINT` | `supabase/.env` (local) / `supabase secrets set` |
| `CRON_SECRET`         | same; must match the cron Vault secret  |

The portal password is **not** an env var — it's stored per-user in Supabase
Vault by the `set_carrier_credentials` RPC and read back server-side via
`get_carrier_secret` (service role only).

## Scheduling

`pg_cron`/`pg_net` and the hourly job are set up by migration
`20260606000006_carrier_auto_sync.sql`. After setting these two Vault secrets,
(re)create the schedule:

```sql
select vault.create_secret('https://<ref>.supabase.co/functions/v1/carrier-sync',
                           'edge_carrier_sync_url');
select vault.create_secret('<same value as CRON_SECRET>',
                           'edge_carrier_sync_cron_secret');
select public.ensure_carrier_sync_schedule();   -- returns 'carrier-sync-hourly scheduled'
```

## Verify / deploy

```bash
deno test supabase/functions          # parser/categorizer parity (matches the Dart test)
deno check supabase/functions/carrier-sync/index.ts
supabase functions serve carrier-sync # local; invoke with a test JWT
supabase functions deploy carrier-sync
```
