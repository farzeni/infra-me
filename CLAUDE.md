# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-hosted infrastructure on a single Hetzner EX44 dedicated server. See `docs/DESIGN.md` for full architectural rationale.

## Stack

- **OS**: Debian 13 (Trixie), Kernel 6.12 LTS
- **Orchestration**: Docker Compose per service stack. `scripts/deploy.sh` runs on the server; `Makefile` triggers it remotely via SSH
- **Ingress**: Caddy (TLS termination, wildcard cert via Cloudflare DNS-01 in prod; `local_certs` locally)
- **Secrets**: SOPS-encrypted `.env.sops` files in Git (age backend). Decrypted to `.env` on the server at deploy time. `.env.example` in each stack for local testing
- **Backups**: Restic → Hetzner Storage Box (SFTP, append-only) + Backblaze B2. Logical DB dumps only, never raw volume files
- **DNS**: Cloudflare (DNS-only, grey cloud) + Porkbun registrar. Wildcard `*.askalotl.net` → server IP

## Repository Layout

```
stacks/              # One subdirectory per service stack
  caddy/
    compose.yaml
    Caddyfile          # Production (Cloudflare DNS-01)
    Caddyfile.local    # Local dev (tls internal via local_certs)
    .env.example
    .env.sops          # Encrypted secrets (committed)
    backup.sh
  openwebui/
    compose.yaml
    .env.example
    .env.sops
    backup.sh
  ...
bootstrap.sh         # First-run server setup (run once as root)
scripts/
  deploy.sh          # Runs ON the server: sops decrypt + docker compose up
Makefile             # Remote triggers: ssh host "git pull && ./scripts/deploy.sh"
.sops.yaml           # SOPS creation rules (age public key)
docs/
  DESIGN.md
  DISASTER_RECOVERY.md  # (to be written)
```

Each stack: `compose.yaml`, `.env.example` (local defaults), `.env.sops` (encrypted prod secrets), config files, `backup.sh`.

## Deployment

```bash
# Deploy all stacks to test
make deploy

# Deploy specific stacks
make deploy-caddy ENV=test
make deploy-openwebui ENV=prod

# Check container status
make status ENV=prod

# Initial server bootstrap (one-time, requires REPO_URL)
make bootstrap ENV=test REPO_URL=https://github.com/user/infra-me.git
```

## Local testing

```bash
cd stacks/<stack>
cp .env.example .env
docker compose up -d
```

`.env.example` uses `*.localhost` domains and `local_certs` TLS — no Cloudflare token needed.

## Secrets workflow

```bash
# Create or update a secret file:
cd stacks/<stack>
cp .env.example .env
vim .env                  # fill in real values
sops --encrypt --input-type dotenv --output-type dotenv .env > .env.sops
git add .env.sops && git commit

# deploy.sh decrypts automatically on the server:
#   sops --decrypt --input-type dotenv --output-type dotenv .env.sops > .env
```

Age key must be present at `/root/.config/sops/age/keys.txt` on the server.

## Networking

All stacks share a single externally-created Docker network `proxy` for ingress. Each stack uses its own internal network for DB/cache traffic. Caddy routes by hostname via `caddy-docker-proxy` labels; no service exposes ports to the host directly.

## Service Tiers

**Active**:
- Caddy — TLS, ingress, reverse proxy
- Open WebUI — AI chat interface

**Planned**:
- Vaultwarden — password manager
- Immich — photo library
- SearXNG — meta search engine
- Uptime Kuma — monitoring

## Backup Mechanics

Each stack has a `backup.sh` that produces logical dumps into a staging directory. A global orchestrator calls each, then Restic snapshots the result. Retention: daily×7, weekly×4, monthly×12, yearly×3. Append-only on Storage Box (prune runs separately). Monthly automated restore test; annual full DR drill on a Hetzner Cloud CX22.

## Operational Principles

- **Configuration as code**: no server state that isn't in Git + Restic
- **Boring choices**: mature tools over novel ones
- **Test environment first**: changes go to a CX22 test VPS before touching production EX44
- **Reversibility**: every decision has a rollback path; avoid deep vendor lock-in
