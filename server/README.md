# PocketPilot backend (`server/`)

The always-on Node/TypeScript service that runs **carrier e-invoice sync** for
all users — and the home for the upcoming **OCR** and **AI categorization**
features. It replaces the old Supabase Edge Function (`supabase/functions/carrier-sync`),
which couldn't scale (60s cap, one sequential cron loop over every user, brittle
Browserless string-Puppeteer).

> This README is the **living whole-project plan** for the backend. It covers the
> current build and the future roadmap (Phases 2 & 3). Keep it current as phases land.

Supabase stays the system of record: the Flutter app still talks to it directly
for all reads/writes, and this backend writes invoices with the **service role**,
exactly as the Edge Function did.

---

## Architecture

One process hosts three things (split into separate web/worker services later if
load demands it):

```
                         ┌──────────────────────────── server/ (Node + TS) ───────────────────────────┐
  Flutter app            │                                                                             │
  "Sync now" ─POST /sync/now (Bearer JWT)─▶ Fastify API ──set status 'running'──▶ Supabase             │
       ▲                 │                      │                                  (carrier_config)     │
       │ polls           │                      └──enqueue {userId}──▶ pg-boss queue (Supabase Postgres)│
       │ carrier_config  │                                                  │                           │
       │                 │   scheduler.ts ──every N min: scan due users──▶ enqueue                      │
       │                 │                                                  │                           │
       │                 │                                            worker.ts (concurrency=N)         │
       │                 │                                                  │                           │
       │                 │   get_carrier_secret (Vault) ◀── runSync ──▶ scrape.ts (Playwright+stealth)  │
       │                 │                                                  │  └─ OcrService (Tesseract)│
       └─────────────────│────────────── ingest.ts ──write invoices──▶ Supabase  (CAPTCHA solve)       │
                         └─────────────────────────────────────────────────────────────────────────────┘
```

**Sync-now flow**

1. App `POST /sync/now` with the Supabase access token as `Authorization: Bearer`.
2. `auth.ts` resolves the user id via Supabase; 401 if invalid.
3. API sets `carrier_config.last_sync_status='running'`, **enqueues** a job
   (`singletonKey=userId` → at most one per user), returns **202** immediately.
4. `worker.ts` (≤ `SYNC_CONCURRENCY` in parallel) reads the Vault password via
   `get_carrier_secret`, runs `scrape.ts`, runs `ingest.ts`, writes
   `last_sync_status='ok'|'error'` + `last_sync_count`. pg-boss retries on failure.
5. App polls `carrier_config` until status leaves `running`.

**Scheduler** (`scheduler.ts`, replaces pg_cron): every `SCHEDULER_INTERVAL_MS`
it scans `carrier_config` for users where `auto_sync_enabled` is on, credentials
are stored (`password_secret_id` not null), and `sync_interval_minutes` has
elapsed since `last_sync_attempt_at` — then enqueues one job each.

### Source map

| Path | Role |
| --- | --- |
| `src/index.ts` | Fastify app: `POST /sync/now`, `GET /healthz`; starts worker + scheduler |
| `src/auth.ts` | Bearer-token → Supabase user id |
| `src/supabase.ts` | service-role admin client + per-token client |
| `src/queue.ts` | pg-boss queue (`carrier-sync`), enqueue + lifecycle |
| `src/worker.ts` | pulls jobs, runs `runSync` up to `SYNC_CONCURRENCY` in parallel |
| `src/scheduler.ts` | periodic due-user scan → enqueue (port of the Edge `dueUserIds`) |
| `src/sync.ts` | `runSync`: status → Vault password → scrape → ingest → status |
| `src/scrape.ts` | Playwright + stealth: login, CAPTCHA (via OCR), paginate, download CSV |
| `src/ocr/` | `OcrService` interface + `TesseractOcr` (Tesseract.js + sharp) |
| `src/lib/` | lifted from the Edge `_shared/`: `ingest`, parser, categorizer, money (+ parity test) |
| `src/spike.ts` | throwaway de-risk script (see below) |

The parser/categorizer in `src/lib/` mirror the Dart `packages/pp_core`; the
`einvoice_csv_parser.test.ts` parity test guards them (same fixture as the Dart test).

---

## Setup & run (local)

```bash
cd server
npm install
cp .env.example .env     # fill in the values below
npx playwright install chromium   # browser binary (the Docker image already has it)

npm run typecheck        # tsc --noEmit
npm test                 # parser/categorizer parity (vitest)
npm run dev              # tsx watch — API + worker + scheduler
```

`GET http://localhost:8080/healthz` → `{ "ok": true }`.

### Environment

| Var | Required | Notes |
| --- | --- | --- |
| `SUPABASE_URL` | ✅ | Same project the app uses |
| `SUPABASE_ANON_KEY` | ✅ | Used only to validate user JWTs |
| `SUPABASE_SERVICE_ROLE_KEY` | ✅ | Reads Vault password, writes invoices/status |
| `SUPABASE_DB_URL` | ✅ | **Session-mode** Postgres conn string (direct `:5432`, not the `:6543` pooler) for pg-boss |
| `HEADLESS` | – | `false` (Docker default) runs a real Chromium under Xvfb — best Cloudflare pass rate |
| `PROXY_URL` | – | Residential/TW proxy, only if Cloudflare blocks the host IP (risk #1) |
| `SYNC_CONCURRENCY` | – | Parallel syncs / browsers (default 2) |
| `SCHEDULER_INTERVAL_MS` | – | Due-user scan cadence (default 60000) |
| `PORT` | – | HTTP port (default 8080) |

> First OCR call downloads `eng.traineddata` (Tesseract.js, cached after).

---

## Deploy (GCP free-tier VM + Cloudflare Tunnel)

The web demo runs the backend on a **Google Cloud Always-Free e2-micro VM** via
Docker, fronted by **Cloudflare Tunnel** for HTTPS. CI builds the image; the VM
only pulls. (Railway/Render are drop-in alternatives — same Dockerfile, pick an
**Asia/Singapore** region; the only changes are where env vars live and how the
image is deployed.)

Keep the Dockerfile's Playwright base tag in lockstep with the `playwright`
version in `package.json` (currently `1.49.0`).

> **e2-micro is 1 GB RAM / shared vCPU** — tight for Chromium + Xvfb + Tesseract.
> Run with `SYNC_CONCURRENCY=1`, add a **2 GB swapfile**, and keep `HEADLESS=false`
> (set in the image). [`docker-compose.yml`](docker-compose.yml) caps container
> memory so an OOM restarts the container, not the VM. Always-Free e2-micro only
> exists in `us-west1`/`us-central1`/`us-east1`; the US→TW latency raises the
> Cloudflare-Turnstile risk (#1) — set `PROXY_URL` if the portal blocks the IP.
> Carrier sync is the only feature this affects; treat it as best-effort.

### One-time VM setup

Create an e2-micro (`us-central1`, Debian/Ubuntu, 30 GB disk), SSH in, copy
[`deploy/setup-vm.sh`](deploy/setup-vm.sh) over, and run it — it installs Docker,
a 2 GB swapfile, cloudflared, and writes a `/opt/pocketpilot/.env` template:

```bash
bash setup-vm.sh
```

Then finish the manual bits it prints:

```bash
# a) Let the VM pull the private image (read:packages PAT, stored once):
echo <GHCR_READ_PAT> | docker login ghcr.io -u j-hop8 --password-stdin
# b) Edit /opt/pocketpilot/.env with real Supabase values (session-mode :5432 DB URL).
# c) Cloudflare Tunnel: route  api.<your-domain> -> http://localhost:8080 , then:
sudo cloudflared service install <TUNNEL_TOKEN>
```

The `docker-compose.yml` and the image are delivered by CI — you don't copy them
manually. After the first deploy: `curl https://api.<your-domain>/healthz` → `{"ok":true}`.

(No Cloudflare-managed domain? Use a Caddy reverse proxy + an `sslip.io`/DuckDNS
hostname for automatic Let's Encrypt TLS instead of the tunnel.)

### CI/CD

[`.github/workflows/backend.yml`](../.github/workflows/backend.yml): on push to
`main` touching `server/**` (or manual **Run workflow**), the `build-push` job
builds the image and pushes `ghcr.io/j-hop8/pocketpilot-server:latest` to GHCR.
Building on CI (not the 1 GB VM) is deliberate.

The `deploy` job (sync `docker-compose.yml` to the VM → SSH → `docker compose pull
&& up -d`) is **gated**:
it only runs when the repo variable **`BACKEND_DEPLOY_ENABLED=true`** is set
(Settings → Secrets and variables → Actions → **Variables**). Leave it unset until
the VM is provisioned — pushes will still build + push the image, just skip the
deploy. When ready, add the secrets `VM_SSH_HOST` / `VM_SSH_USER` / `VM_SSH_KEY`
and set the variable. PRs run typecheck + tests via
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

Point the Flutter app at the service with the **https** tunnel URL:
`--dart-define BACKEND_URL=https://api.<your-domain>` (set as the `BACKEND_URL`
GitHub secret). CORS already reflects any origin (Bearer-JWT auth, no cookies), so
no per-origin config is needed.

Single instance is assumed (the scheduler runs in-process). To scale out, run one
web+worker instance and move the scheduler to a leader-locked job.

### Supabase migration (one-time, at cutover)

Stop the old pg_cron job so it and the backend scheduler don't both fire:

```bash
supabase db push   # applies supabase/migrations/20260606000007_drop_carrier_cron.sql
```

The Vault RPCs (`set_carrier_credentials` / `get_carrier_secret`) and sync-setting
columns are unchanged. The Edge Function can stay deployed as a fallback during
cutover, then be deleted once this backend is verified live.

---

## De-risking spike (run first)

The three hard problems are front-loaded into `npm run spike`, which runs the
real scrape against a test account and writes artifacts to `./.spike`:

```bash
PHONE=09xxxxxxxx PASSWORD=secret HEADLESS=false npm run spike
```

1. **Cloudflare Turnstile from a datacenter IP** — stealth + headful (Xvfb) +
   zh-TW locale/timezone + Asia region; if still blocked, set `PROXY_URL` to a
   residential/TW exit. Manual CSV import in the app is the permanent fallback.
2. **Tesseract CAPTCHA accuracy** — `sharp` preprocessing (grayscale → upscale →
   normalize → median → threshold) + digit whitelist + PSM 7; wrong-length reads
   are discarded and re-solved cheaply (no longer time-boxed by a 60s cap). Tune
   `preprocessCaptcha` against the saved `./.spike/captcha-*.png` samples.
3. **Unconfirmed 消費明細 export selectors** — the spike confirms the search →
   detail → 全選 → 下載CSV檔 → 下一頁 flow end-to-end; on failure it dumps a
   screenshot + DOM (`login-failed.*`) so selectors can be corrected.

---

## Roadmap

### Phase 1 — Core sync ✅ (this build)
Self-hosted Playwright scrape + Tesseract CAPTCHA, JWT-authed `/sync/now`,
pg-boss queue + worker (retries/concurrency), in-process scheduler, Flutter wired
via `BACKEND_URL`, pg_cron unscheduled.

### Phase 2 — OCR receipts / e-invoices (future)
Reuse the **same `OcrService`** (Tesseract.js, receipt-tuned preprocessing/PSM).

- `OcrService.extractText` is already on the interface.
- Add `POST /ocr/receipt` (multipart image) → preprocess → OCR → parse into a
  draft `{ merchant, date, total, items[] }` returned for **user confirmation**
  before insert (don't auto-write low-confidence OCR).
- Flutter: a "Scan receipt" entry point (camera/file) → review screen → insert via
  the existing invoice path.

### Phase 3 — AI auto-categorize (future)
Introduce a `Categorizer` interface in `src/lib/ingest.ts`; the default stays the
rule-based `categorizeKey`. Add a **Gemini-backed** implementation as an override
(user chose Gemini specifically for categorization — separate from the
open-source OCR choice), plus an optional "re-categorize existing invoices"
endpoint. Wrapping it behind the interface keeps ingest unchanged.

### Cleanup (post-cutover)
Delete `supabase/functions/carrier-sync` + `_shared/`, and drop the
"automatic carrier sync isn't live yet" copy in the app's CSV-import card.
