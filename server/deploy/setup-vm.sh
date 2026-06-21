#!/usr/bin/env bash
# One-shot setup for the PocketPilot backend on a fresh GCP e2-micro VM
# (Debian/Ubuntu). Idempotent — safe to re-run. Run as a sudo-capable user:
#
#   bash setup-vm.sh
#
# It installs Docker, a 2 GB swapfile (e2-micro has only 1 GB RAM), cloudflared,
# and creates /opt/pocketpilot with a .env template. The docker-compose.yml and
# the container image are delivered by CI (.github/workflows/backend.yml).
set -euo pipefail

APP_DIR=/opt/pocketpilot
GHCR_USER=j-hop8

echo "==> 1/4 Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER" || true
  echo "   Docker installed. Run 'newgrp docker' or re-login so your user can use it."
else
  echo "   Docker present: $(docker --version)"
fi

echo "==> 2/4 Swap (2 GB)"
if ! sudo swapon --show 2>/dev/null | grep -q '/swapfile'; then
  sudo fallocate -l 2G /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  echo "   2 GB swap enabled."
else
  echo "   Swap already present."
fi

echo "==> 3/4 App dir + .env template"
sudo mkdir -p "$APP_DIR"
sudo chown "$USER:$USER" "$APP_DIR"
if [ ! -f "$APP_DIR/.env" ]; then
  cat > "$APP_DIR/.env" <<'EOF'
# Fill in real values — see server/.env.example for full docs.
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY
# SESSION-mode connection string (direct :5432, NOT the :6543 pooler) — pg-boss
# needs LISTEN/NOTIFY + advisory locks:
SUPABASE_DB_URL=postgresql://postgres.YOUR_REF:PASSWORD@aws-0-REGION.pooler.supabase.com:5432/postgres
# e2-micro tuning:
HEADLESS=false
SYNC_CONCURRENCY=1
EOF
  echo "   Wrote $APP_DIR/.env TEMPLATE — EDIT it with real values before deploying."
else
  echo "   $APP_DIR/.env already exists — leaving it untouched."
fi

echo "==> 4/4 cloudflared (HTTPS tunnel)"
if ! command -v cloudflared >/dev/null 2>&1; then
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
    | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y cloudflared
else
  echo "   cloudflared present: $(cloudflared --version 2>/dev/null | head -1)"
fi

cat <<EOF

================================ NEXT STEPS (manual) ================================
a) Let the VM pull the private image (read:packages PAT):
     echo <GHCR_PAT> | docker login ghcr.io -u $GHCR_USER --password-stdin

b) Edit $APP_DIR/.env with real Supabase values (session-mode DB URL!).

c) Cloudflare Tunnel for HTTPS (dashboard -> Zero Trust -> Networks -> Tunnels):
   create a tunnel, route  api.<your-domain> -> http://localhost:8080 , then:
     sudo cloudflared service install <TUNNEL_TOKEN>

d) In GitHub repo Settings -> Secrets and variables -> Actions:
     Secrets:   VM_SSH_HOST, VM_SSH_USER, VM_SSH_KEY
     Variables: BACKEND_DEPLOY_ENABLED = true
   Then re-run the "Backend" workflow (Actions -> Backend -> Run workflow).
   CI will copy docker-compose.yml here, pull the image, and start it.

Verify:  curl https://api.<your-domain>/healthz   ->   {"ok":true}
====================================================================================
EOF
echo "Setup script done."
