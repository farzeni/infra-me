# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-hosted infrastructure on a single Hetzner EX44 dedicated server. See `docs/DESIGN.md` for full architectural rationale.

## Stack

- **OS**: Debian 13 (Trixie), Kernel 6.12 LTS
- **Orchestration**: Docker Compose per service stack + Ansible for deployment (GitOps-style)
- **Ingress**: Caddy (TLS termination, wildcard cert via Cloudflare DNS-01)
- **Auth/SSO**: Authelia with OIDC (file-based users, argon2id, TOTP)
- **Secrets**: SOPS + age — `.env.sops.yaml` encrypted in Git, decrypted to `.env` (mode 600) by Ansible at deploy time
- **Backups**: Restic → Hetzner Storage Box (SFTP, append-only) + Backblaze B2. Logical DB dumps only (`mongodump`, `pg_dumpall`, SQLite `.backup`), never raw volume files
- **DNS**: Cloudflare (DNS-only, grey cloud) + Porkbun registrar. Wildcard `*.askalotl.com` → server IP

## Repository Layout (intended, being built)

```
stacks/          # One subdirectory per service stack
  caddy/
  authelia/
  vaultwarden/
  librechat/
  immich/
  ...
ansible/         # Playbooks and roles
bootstrap.sh     # First-run server hardening
docs/
  DESIGN.md
  DISASTER_RECOVERY.md  # (to be written)
```

Each stack directory is self-contained: `compose.yaml`, `.env.sops.yaml`, config files, optional `backup.sh`.

## Deployment

```bash
# Deploy from operator's laptop
ansible-playbook deploy.yaml

# Decrypt secrets during deploy (Ansible handles this automatically)
# Requires age key at ~/.config/sops/age/keys.txt

# Manual SOPS operations
sops --decrypt stacks/<name>/.env.sops.yaml > stacks/<name>/.env
sops stacks/<name>/.env.sops.yaml   # edit in place
```

## Networking

All stacks share a single externally-created Docker network `proxy` for ingress. Each stack has its own internal network for DB/cache traffic (isolated from other stacks). Caddy routes by hostname; no service exposes ports directly to the host.

## Service Tiers

**Tier 1 (core, deploy first)**: Caddy → Authelia+Redis → Vaultwarden → LibreChat+MongoDB+Meilisearch → Immich+Postgres+Redis+ML → SearXNG → Uptime Kuma

**Tier 2 (educational)**: Kiwix, Hedgedoc, Forgejo, Audiobookshelf

**Tier 3 (conditional)**: Nextcloud, Jellyfin, Matrix Synapse — only if real need emerges

## Auth Model

- OIDC via Authelia: LibreChat, Immich, Forgejo, Hedgedoc
- Native auth (no SSO): Vaultwarden — deliberately isolated so password manager works without identity provider
- No self-registration on any service (`ALLOW_REGISTRATION=false` pattern)
- Monitoring dashboards: internal hostname or Tailscale only, no public exposure

## Secrets Pattern

`.env.sops.yaml` uses SOPS with age. Only values are encrypted; keys are visible in diffs. The age private key lives at `~/.config/sops/age/keys.txt` on the operator's laptop — never committed. Physical paper backup in a sealed envelope is the recovery path.

## Backup Mechanics

Each stack has a `backup.sh` that produces logical dumps into a staging directory. A global orchestrator calls each, then Restic snapshots the result. Retention: daily×7, weekly×4, monthly×12, yearly×3. Append-only on Storage Box (prune runs separately). Monthly automated restore test; annual full DR drill on a Hetzner Cloud CX22.

## Operational Principles

- **Configuration as code**: no server state that isn't in Git + Restic
- **Boring choices**: mature tools over novel ones
- **Test environment first**: changes go to a CX22 test VPS before touching production EX44
- **Reversibility**: every decision has a rollback path; avoid deep vendor lock-in
