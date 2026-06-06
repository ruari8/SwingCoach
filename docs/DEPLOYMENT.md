# SwingCoach Deployment

This document captures the backend deployment model without storing machine-specific secrets, raw origin IPs, or one-off incident notes in the public repository.

## Public Endpoint

The iOS app's deployed backend target is:

```text
https://swingcoach-api.ruari.dev
```

The API is a FastAPI app served by Uvicorn behind nginx. Uvicorn should bind only to localhost; public traffic should arrive through the reverse proxy.

```text
Cloudflare -> nginx -> 127.0.0.1:8000 or 127.0.0.1:8001 -> FastAPI
```

## Deployment Shape

The deployment uses a blue/green layout:

```text
SwingCoach-blue/      inactive or active checkout
SwingCoach-green/     inactive or active checkout
SwingCoach-shared/    local-only env, model files, and cloned external repos
SwingCoach-deploy/    deployment script, active-slot marker, nginx upstream template
```

The shared directory holds files that should not be committed:

```text
SwingCoach-shared/.env
SwingCoach-shared/models/        optional, if needed
SwingCoach-shared/sam_3d_body/   optional, if needed
```

Each slot links the local backend environment file:

```text
backend/.env -> SwingCoach-shared/.env
```

## Services

There are two systemd services, one per slot:

```text
swingcoach-api-blue   -> backend on 127.0.0.1:8000
swingcoach-api-green  -> backend on 127.0.0.1:8001
```

Useful checks on the VPS:

```bash
systemctl status swingcoach-api-blue --no-pager
systemctl status swingcoach-api-green --no-pager
journalctl -u swingcoach-api-blue -n 100 --no-pager
journalctl -u swingcoach-api-green -n 100 --no-pager
```

## Nginx

nginx should proxy to whichever local slot is active:

```nginx
set $swingcoach_upstream http://127.0.0.1:8000;
```

or:

```nginx
set $swingcoach_upstream http://127.0.0.1:8001;
```

Recommended hardening:

- Restrict direct origin access to Cloudflare IP ranges.
- Deny sensitive probe paths such as `/.env` and `/.git`.
- Keep Uvicorn bound to localhost only.
- Test nginx config before every reload.

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## DNS And HTTPS

DNS is managed in Cloudflare.

The API hostname should point to the VPS through a proxied Cloudflare record. Keep the raw origin IP in the private deployment notes or provider console, not in this repository.

Cloudflare Universal SSL normally covers `*.ruari.dev`, not nested names like `*.*.ruari.dev`, so the app uses `swingcoach-api.ruari.dev` rather than a deeper subdomain.

The VPS should terminate HTTPS through certbot-managed certificates or an equivalent managed certificate setup.

## Manual Deployment

Deploy from the VPS with the blue/green deploy script.

Expected flow:

```text
1. Read the current live slot.
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
12. Send deploy notifications if configured.
```

The previous live slot stays running. A failed deploy should not take down the healthy live version.

## Preflight Checks

The deploy script should fail before switching nginx if required checks do not pass.

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

SAM 3D Body is currently optional. If SAM 3D becomes required for production behavior, add a preflight check for the shared `sam_3d_body` folder and any required model files.

## Notifications

Deploy notifications are optional and configured in a local-only env file under the deployment tooling directory. The file should be gitignored and readable only by the deploy user.

Notification failures should be non-fatal; deployment health should depend on preflight checks, service restart, nginx validation, and `/health`.

## Cloudflare API Rule

The API hostname must not receive interactive browser challenges. Mobile clients and backend checks need plain API responses.

Recommended Cloudflare rule:

```text
If hostname equals swingcoach-api.ruari.dev
Then skip interactive challenges such as Managed Challenge and Browser Integrity Check
```

Keep the Cloudflare proxy enabled if nginx is configured to accept only Cloudflare-originated traffic.

## Useful Commands

Local health checks:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8001/health
```

Public health check:

```bash
curl https://swingcoach-api.ruari.dev/health
```

Manual rollback is an upstream switch to the previously healthy slot followed by nginx validation and reload.
