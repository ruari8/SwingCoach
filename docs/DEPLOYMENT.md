# SwingCoach Deployment

This document describes how the SwingCoach backend is deployed on the VPS.

## Current Setup

Production API URL:

```text
https://swingcoach-api.ruari.dev
```

The backend is a FastAPI app served by Uvicorn behind nginx. Uvicorn is only bound to localhost; it is not exposed directly to the internet.

```text
Cloudflare -> nginx -> 127.0.0.1:8000 or 127.0.0.1:8001 -> FastAPI
```

The VPS runs two local checkouts of the same GitHub repo:

```text
/home/deploy/apps/SwingCoach-blue
/home/deploy/apps/SwingCoach-green
```

Shared local-only deployment state lives outside those checkouts:

```text
/home/deploy/apps/SwingCoach-shared/.env
/home/deploy/apps/SwingCoach-shared/models/        optional, if needed
/home/deploy/apps/SwingCoach-shared/sam_3d_body/   optional, if needed
```

Deployment tooling lives here:

```text
/home/deploy/apps/SwingCoach-deploy
```

Important files:

```text
/home/deploy/apps/SwingCoach-deploy/deploy-bluegreen.sh
/home/deploy/apps/SwingCoach-deploy/live_slot
/home/deploy/apps/SwingCoach-deploy/nginx-upstream.conf
/home/deploy/apps/SwingCoach-deploy/telegram.env
```

`telegram.env` contains secrets and must not be committed.

## Services

There are two systemd services:

```text
swingcoach-api-blue  -> /home/deploy/apps/SwingCoach-blue/backend  -> 127.0.0.1:8000
swingcoach-api-green -> /home/deploy/apps/SwingCoach-green/backend -> 127.0.0.1:8001
```

The old one-slot service is disabled:

```text
swingcoach-api
```

Check service state:

```bash
systemctl status swingcoach-api-blue --no-pager
systemctl status swingcoach-api-green --no-pager
```

Read logs:

```bash
journalctl -u swingcoach-api-blue -n 100 --no-pager
journalctl -u swingcoach-api-green -n 100 --no-pager
```

## Nginx

The nginx site config is:

```text
/etc/nginx/sites-available/swingcoach-api
```

It is enabled through:

```text
/etc/nginx/sites-enabled/swingcoach-api
```

Nginx includes this generated upstream file:

```text
/home/deploy/apps/SwingCoach-deploy/nginx-upstream.conf
```

That file points nginx at the active slot:

```nginx
set $swingcoach_upstream http://127.0.0.1:8000;
```

or:

```nginx
set $swingcoach_upstream http://127.0.0.1:8001;
```

The nginx config also includes:

```nginx
include /etc/nginx/cloudflare-allow.conf;
```

That means the origin only accepts Cloudflare IP ranges. Direct requests to the VPS IP are denied.

Sensitive probe paths such as `/.env` and `/.git` are explicitly denied by nginx.

## DNS And HTTPS

DNS is managed in Cloudflare.

The active DNS record should be:

```text
Type: A
Name: swingcoach-api
Value: 46.224.210.96
Proxy status: Proxied / orange cloud
TTL: Auto
```

Do not use `api.swingcoach.ruari.dev` unless Cloudflare SSL is configured to cover that nested hostname. Cloudflare Universal SSL normally covers `*.ruari.dev`, not `*.*.ruari.dev`.

HTTPS is configured with certbot on the VPS:

```text
/etc/letsencrypt/live/swingcoach-api.ruari.dev/fullchain.pem
/etc/letsencrypt/live/swingcoach-api.ruari.dev/privkey.pem
```

Certbot installed automatic renewal.

## Manual Deployment

Deploy from the VPS:

```bash
/home/deploy/apps/SwingCoach-deploy/deploy-bluegreen.sh
```

Expected flow:

```text
1. Read current live slot from live_slot.
2. Choose the inactive slot as candidate.
3. Fetch latest origin/main in the candidate checkout.
4. Reset candidate to origin/main.
5. Link shared .env and optional shared model folders.
6. Install backend/requirements.txt.
7. Run preflight checks.
8. Restart candidate systemd service.
9. Wait for candidate /health to pass.
10. Switch nginx upstream to candidate.
11. Reload nginx.
12. Send Telegram success/failure notification.
```

Example:

```text
Live: blue
Candidate: green
Deploy updates green
If green is healthy, nginx switches to 127.0.0.1:8001
Next deploy updates blue
```

The previous live slot is kept running. A failed deploy should not take down the healthy live version.

## Preflight Checks

The deploy script fails before switching nginx if required checks do not pass.

Required `.env` keys:

```text
R2_ACCOUNT_ID
R2_ACCESS_KEY_ID
R2_SECRET_ACCESS_KEY
R2_BUCKET_NAME
```

Import and route checks:

```text
import main
main.ANALYSIS_AVAILABLE must be true
GET /health must exist
GET /upload-url must exist
POST /mock/analyze must exist
```

Candidate health check:

```text
http://127.0.0.1:<candidate-port>/health
```

The response must include:

```json
{
  "r2_configured": true,
  "analysis_ready": true
}
```

SAM 3D Body is currently optional. The service logs:

```text
SAM 3D Body not available: No module named 'sam_3d_body'
```

That is not treated as a deployment failure. If SAM 3D becomes required, add a preflight check for the shared `sam_3d_body` folder and any required model files.

## Shared Secrets And Gitignored Files

Do not commit secrets.

The real backend env file is:

```text
/home/deploy/apps/SwingCoach-shared/.env
```

Each slot links to it:

```text
backend/.env -> /home/deploy/apps/SwingCoach-shared/.env
```

For large local-only or gitignored files, prefer this pattern:

```text
/home/deploy/apps/SwingCoach-shared/models/
/home/deploy/apps/SwingCoach-shared/sam_3d_body/
```

Then link them into each slot from the deploy script.

If a future release requires a new env key or local model file, add it to the deploy preflight. The deploy should fail before switching traffic if the VPS is missing required state.

## Telegram Notifications

Deploy notifications are configured through:

```text
/home/deploy/apps/SwingCoach-deploy/telegram.env
```

Format:

```env
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
```

The file is local-only and should be mode `600`.

The deploy script sends:

```text
deploy started
deploy failed with reason
deploy succeeded
```

If Telegram config is missing or invalid, deploys still run; notification failures are non-fatal.

## GitHub Actions Decision

GitHub Actions is not used.

Reason:

```text
Manual deploys are simpler, avoid GitHub Actions billing concerns, and keep deployment control explicit for now.
```

Current approach:

```text
git push from development machine
SSH into VPS
run deploy-bluegreen.sh manually
```

A later MacBook hook can run the same VPS command after pushing:

```bash
ssh deploy@ruari-vps '/home/deploy/apps/SwingCoach-deploy/deploy-bluegreen.sh'
```

If using Tailscale from the MacBook, prefer the Tailscale hostname/IP rather than exposing SSH publicly.

## Current Known Issue

Cloudflare is currently returning a managed challenge for the public API URL.

Observed public health behavior:

```text
https://swingcoach-api.ruari.dev/health -> Cloudflare 403 challenge
```

Local origin health is good:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8001/health
```

Both slots return:

```json
{"status":"healthy","r2_configured":true,"analysis_ready":true}
```

To fix the public API, adjust Cloudflare security/WAF rules for this hostname so API clients are not given interactive browser challenges.

Recommended Cloudflare rule:

```text
If hostname equals swingcoach-api.ruari.dev
Then skip/disable Managed Challenge, Browser Integrity Check, and similar interactive challenge features
```

Keep the orange cloud proxy enabled. The VPS nginx config already restricts origin access to Cloudflare IPs.

## Useful Commands

Show live slot:

```bash
cat /home/deploy/apps/SwingCoach-deploy/live_slot
cat /home/deploy/apps/SwingCoach-deploy/nginx-upstream.conf
```

Local health:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8001/health
```

Public health:

```bash
curl https://swingcoach-api.ruari.dev/health
```

Test nginx:

```bash
sudo nginx -t
```

Reload nginx:

```bash
sudo systemctl reload nginx
```

Manual rollback is just another upstream switch. For example, to point nginx at blue:

```bash
printf 'set $swingcoach_upstream http://127.0.0.1:8000;\n' > /home/deploy/apps/SwingCoach-deploy/nginx-upstream.conf
printf 'blue\n' > /home/deploy/apps/SwingCoach-deploy/live_slot
sudo nginx -t
sudo systemctl reload nginx
```

To point nginx at green:

```bash
printf 'set $swingcoach_upstream http://127.0.0.1:8001;\n' > /home/deploy/apps/SwingCoach-deploy/nginx-upstream.conf
printf 'green\n' > /home/deploy/apps/SwingCoach-deploy/live_slot
sudo nginx -t
sudo systemctl reload nginx
```
