# Development

Build, test, and deployment notes for PocketPilot. For a product overview see
[`README.md`](README.md).

## Run

```sh
cp dart_defines.example.json dart_defines.json   # fill in your Supabase URL + anon key
flutter pub get
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

See [`supabase/README.md`](supabase/README.md) for the database schema, migrations,
and the carrier-sync credential security notes.

## Test

```sh
flutter test       # includes the e-invoice CSV parser + categorizer tests
flutter analyze
```

## Deploy (web demo)

The app deploys to **Cloudflare Pages**; the optional carrier-sync backend runs on a
**Google Cloud free-tier VM**. CI/CD is GitHub Actions (full auto-deploy).

### Pieces

| Piece | Host | Workflow |
| --- | --- | --- |
| Flutter web (this app) | Cloudflare Pages | [`.github/workflows/frontend.yml`](.github/workflows/frontend.yml) |
| Node backend (`server/`) | GCP e2-micro VM (Docker) | [`.github/workflows/backend.yml`](.github/workflows/backend.yml) — see [`server/README.md`](server/README.md#deploy-gcp-free-tier-vm--cloudflare-tunnel) |
| Supabase (DB/Auth/Edge Fns) | Supabase Cloud | `supabase db push` / `supabase functions deploy` (manual) |

The backend is **only** used by carrier auto-sync — everything else works without it.
You can ship the frontend first and add the backend later.

### One-time setup

1. **Cloudflare Pages project** named `pocketpilot` (Direct Upload / CI deploy —
   Cloudflare has no Flutter buildpack, so CI builds and uploads `build/web`).
   Create an API token scoped to *Account → Cloudflare Pages → Edit* and note the
   Account ID.
2. **GitHub repo secrets** (Settings → Secrets and variables → Actions):
   `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_URL`,
   `SUPABASE_ANON_KEY`, `GOOGLE_WEB_CLIENT_ID`, `BACKEND_URL`
   (the **https** backend URL — see below). Backend deploy also needs
   `VM_SSH_HOST`, `VM_SSH_USER`, `VM_SSH_KEY`.
3. **Google Cloud Console → OAuth client:** add the Pages URL to
   *Authorized JavaScript origins* (required by `google_sign_in_web`).
4. **Supabase → Authentication → URL Configuration:** add the Pages URL to
   Site URL + Redirect URLs.

> **HTTPS is mandatory for the backend.** The Pages site is HTTPS, so the browser
> blocks calls to a plain `http://<vm-ip>:8080` (mixed content). `BACKEND_URL`
> must be an `https://` host — we use Cloudflare Tunnel (see the server README).

### CI/CD

- Push to `main` → frontend builds (analyze + test gate) and deploys to Pages
  production; backend (on `server/**` changes) rebuilds the image, pushes to GHCR,
  and the VM pulls + restarts.
- Pull requests → Cloudflare Pages **preview** URL; backend PRs run typecheck +
  tests ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

### Build locally for web

```sh
flutter build web --release --dart-define-from-file=dart_defines.json
# output in build/web — for production set BACKEND_URL to the https backend host
```
