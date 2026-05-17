# Backlog

> Status: `[ ]` todo · `[~]` in progress · `[x]` done

---

## Phase 1 — Repo skeleton
`[ ]` Setup sops

## Phase 2 — Bootstrap + test VPS
`[ ]` Write `bootstrap.sh` (non-root user, SSH hardening, ufw, Docker, fail2ban).
`[ ]` Provision CX22 on Hetzner with Debian 13.
`[ ]` Point `*.test.<domain>` DNS → CX22 IP.

## Phase 3 — Ansible scaffolding
`[ ]` Inventory file (test + prod groups).
`[ ]` Idempotent `deploy.yaml` playbook.
`[ ]` SOPS decryption step (age key, `.env` drop with mode 600).
`[ ]` Create external `proxy` Docker network.

## Phase 4 — Caddy
`[ ]` `stacks/caddy/` compose + config.
`[ ]` Wildcard TLS via Cloudflare DNS-01 challenge.
`[ ]` Smoke-test with a `/ping` handler before moving on.
> **Gate**: TLS must be green here. Nothing else works without it.

## Phase 5 — Authelia
`[ ]` `stacks/authelia/` compose + config + Redis sidecar.
`[ ]` File-based users, argon2id, TOTP.
`[ ]` Forward-auth middleware wired in Caddy.
`[ ]` Cookie scoped to root domain.
> **Gate**: Must be stable before any OIDC-consuming service.

## Phase 6 — Vaultwarden
`[ ]` `stacks/vaultwarden/` compose + `.env.sops.yaml`.
`[ ]` Native auth only (no OIDC — deliberate isolation).
`[ ]` Confirms stack pattern + Caddy routing without OIDC complexity.

## Phase 7 — LibreChat
`[ ]` `stacks/librechat/` compose: LibreChat + MongoDB + Meilisearch.
`[ ]` OIDC client registered in Authelia.
`[ ]` `ALLOW_REGISTRATION=false`.

## Phase 8 — Backup
`[ ]` Per-stack `backup.sh` (logical dumps: `mongodump`, `pg_dumpall`, SQLite `.backup`).
`[ ]` Global orchestrator script calling each stack's backup.
`[ ]` Restic repo on Hetzner Storage Box (SFTP, append-only key).
`[ ]` Restic repo on Backblaze B2.
`[ ]` Retention policy: daily×7, weekly×4, monthly×12, yearly×3.
`[ ]` Restore test on a clean throwaway VPS.

## Phase 9 — Immich
`[ ]` `stacks/immich/` compose: Immich + Postgres (vectorchord) + Redis + ML worker.
`[ ]` OIDC client registered in Authelia.
`[ ]` Backup script for Postgres dump + originals path.

## Phase 10 — Educational services
`[ ]` SearXNG.
`[ ]` Kiwix.
`[ ]` Hedgedoc (OIDC).
`[ ]` Forgejo (OIDC).
`[ ]` Audiobookshelf.
> Deploy one at a time; validate each before the next.

## Phase 11 — Monitoring
`[ ]` `stacks/uptime-kuma/` compose.
`[ ]` Internal/Tailscale-only hostname (no public exposure).
`[ ]` Telegram alert channel configured.

## Phase 12 — DR runbook
`[ ]` Write `docs/DISASTER_RECOVERY.md` based on concrete restore experience.
`[ ]` Full restore drill on a throwaway CX22 (time the whole process).

## Phase 13 — Production
`[ ]` Order Hetzner EX44.
`[ ]` Run `installimage` → Debian 13.
`[ ]` Run `bootstrap.sh`.
`[ ]` `ansible-playbook deploy.yaml` targeting prod inventory.
`[ ]` Switch Cloudflare DNS from CX22 → EX44.
`[ ]` Family onboarding (accounts, Vaultwarden, Immich).

## Phase 14 — Cleanup
`[ ]` Destroy test CX22.
`[ ]` Remove `*.test.<domain>` DNS records.
`[ ]` Delete test user accounts from all services.
