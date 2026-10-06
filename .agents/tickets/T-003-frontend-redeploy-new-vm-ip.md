# T-003: Point the web demo at the VM's new IP

**Goal:** The GCP VM's ephemeral IP changed 35.212.221.51 → 35.212.196.17, breaking demo
carrier sync (the web build has the dead `BACKEND_URL` baked in). Make the frontend
manually redeployable and rebuild it against the updated secret.

**Files in scope:** `.github/workflows/frontend.yml`, `server/deploy/nginx/pocketpilot.conf`

**Do NOT touch:** app code (`lib/**`, `server/src/**`), other workflows

**Acceptance criteria:**
- [ ] `frontend.yml` has `workflow_dispatch`; a run on `main` does a prod `wrangler deploy`,
      PRs / other branches still only `versions upload`
- [ ] nginx template `server_name` matches the new sslip host
- [ ] After merge, the deployed `main.dart.js` references `https://35.212.196.17.sslip.io`

**Verify:** `curl -s https://pocketpilot.pocketpilot.workers.dev/main.dart.js | grep -o 'https://[0-9.]*\.sslip\.io'`

**Prereqs (manual, done 2026-10-06):** IP promoted to static, cert re-issued on VM,
`BACKEND_URL` + `VM_SSH_HOST` secrets updated.

**Owner:** claude
