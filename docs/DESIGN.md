# Infrastructure Design Document

This document captures the architectural decisions for this self-hosted infrastructure, including the reasoning behind each choice. It serves as both a reference for the operator and a guide for future evolution.

Last updated: 2026-05-18

## 1. Goals and Non-Goals

### Primary Goals

Provide self-hosted alternatives to commercial services, retaining control over data and access.

- AI access via LibreChat, with conversations stored locally
- Password management (Vaultwarden)
- Photo storage (Immich)
- Educational tools: offline Wikipedia, meta search engine, ebook library
- Notes and private code repositories

### Secondary Goals

- Reliability sufficient for daily use (not 99.99% SLA, but no frequent outages)
- Operational simplicity: maintainable in spare time alongside full-time work
- Recoverable from disaster within 4-6 hours
- Cost predictability

### Non-Goals

- High availability with automatic failover
- Multi-region redundancy
- Replacement for all commercial services (no email self-hosting, no social media)
- Enterprise compliance (HIPAA, SOC2, etc.)

## 2. Hosting Decision

### Decision: Hetzner Dedicated Server (EX44)

After evaluating multiple options, the chosen hosting is a single Hetzner dedicated server, EX44 model, purchased new at standard list price (~44€/month).

### Alternatives Considered and Rejected

**Hetzner Cloud (CCX/CX VMs)**: Cheaper for small workloads but limited by virtualization overhead and less generous I/O. EX44 dedicated provides more performance per euro for sustained workload.

**Hetzner Server Auction**: Initially preferred for cost savings (~38-42€ for equivalent hardware). Auction prices rose significantly (Feb-May 2026: +24%), erasing the advantage. Current auction minimum (~48€) is now higher than new EX44 list price. Decision made to skip auction in favor of new EX44.

**Self-hosting at home**: Operator has FTTH 900/300 Mbps with static public IP, hardware would be viable. Rejected because services require always-on availability that residential infrastructure cannot guarantee (power, ISP outages, no dedicated cooling). Home option may be revisited in future as backup target.

**Hybrid (home + small cloud)**: Considered but added complexity without proportional benefit for the use case.

### Hardware Specifications

- CPU: Intel Core i5-13500 (14 cores / 20 threads, Raptor Lake, 2022)
- RAM: 64 GB DDR4
- Storage: 2× 512 GB NVMe Gen4 in software RAID1
- Network: 1 Gbit/s, unlimited traffic
- Datacenter: Falkenstein (FSN) or Nuremberg (NBG) for lowest latency from Italy

### Why Not GPU

LLM inference uses commercial APIs (Anthropic, OpenAI) configured with opt-out from training. Local inference was considered (would require Mac mini or GPU host) but rejected: commercial APIs do not build persistent user profiles from API calls the way consumer products do with logged-in accounts. Future revisit possible if local inference quality becomes competitive.

## 3. Operating System

### Decision: Debian 13 (Trixie)

- Released August 2025, full support until August 2028, LTS until June 2030
- 9+ months of post-release stability at time of deployment
- Kernel 6.12 LTS
- Minimal, predictable, no telemetry, no Canonical-specific tooling

### Alternatives Rejected

**Ubuntu Server 24.04 LTS**: Equivalent technical capability but includes snap by default, motd advertising, Ubuntu Pro nags, and telemetry that requires explicit opt-out. Adds noise without benefit for this use case.

**Debian 12 (Bookworm)**: Stable but would require major upgrade within the planning horizon. Starting from 13 provides 4+ years of stability without upgrade pressure.

**Alpine, NixOS, Fedora Server, RHEL clones**: Each has merits but adds operational complexity or learning curve not justified by the use case.

## 4. Orchestration

### Decision: Docker Compose + bootstrap.sh + Git (GitOps-style)

The orchestration approach is intentionally simple: Docker Compose files per stack, version controlled in Git, deployed via a shell script that runs on the server. Configuration is the source of truth in Git; the server is execution.

There is no configuration management tool (Ansible, Chef, Puppet). Initial server setup is handled by `bootstrap.sh`, a plain bash script that runs once as root. Ongoing deploys are handled by `scripts/deploy.sh`, which runs on the server itself (triggered remotely via SSH from the operator's laptop). This keeps the toolchain minimal: bash, git, sops, docker.

### Alternatives Rejected

**Kubernetes / K3s**: Originally considered (operator has K8s experience). Rejected because orchestration value of K8s shines with multiple nodes, autoscaling, rolling deployments — none of which apply to a single-host personal workload. The complexity tax is not paid back.

**Docker Swarm**: Operator's previous setup, explicitly unsatisfactory. Maintenance mode by Docker Inc.

**Portainer**: Adds UI but obscures what is happening underneath. Operator prefers direct control.

**Coolify and similar PaaS-on-self-hosted (Dokploy, CapRover)**: Rejected because GitOps purity is a stated value: configuration must live in Git, not in a control plane database.

**Ansible**: Used in an earlier iteration for bootstrap. Removed in favour of a plain bash script. Ansible adds a dependency on the operator's laptop (Python, collections, inventory files) without meaningful benefit for a one-time bootstrap of a single server. A bash script is more portable, easier to audit, and trivially run via `ssh root@host "bash -s" < bootstrap.sh`.

**Proxmox + VMs**: Rejected because the server hosts a single personal environment; the abstraction layer adds complexity without isolation benefit.

### Pattern

Each stack lives in its own directory under `stacks/`. A stack is self-contained: `compose.yaml`, `.env.example` (local defaults), `.env.sops` (encrypted prod secrets), configuration files, `backup.sh`. Stacks share a single Docker network `proxy` (externally created) for ingress. Each stack has its own internal network for database/cache traffic, isolated from other stacks.

## 5. Networking and Ingress

### Decision: Caddy as Single Ingress

Caddy serves as the only public-facing reverse proxy. It terminates TLS, handles wildcard certificates via Cloudflare DNS challenge, and routes traffic to internal services by hostname.

### Alternatives Considered

**Traefik**: Equivalent capability. Caddy chosen for simpler configuration (Caddyfile is more readable than Traefik labels) and automatic HTTPS without configuration.

**Nginx + Certbot**: More manual configuration, no benefit for this use case.

**Cloudflare Tunnel**: Would eliminate need for open ports on the server but adds dependency on Cloudflare for traffic routing (not just DNS). Rejected to keep architecture simpler and provider-independent.

### DNS Strategy

- Domain registered through Porkbun for low cost and privacy
- DNS managed by Cloudflare (free tier)
- Wildcard A record `*.<domain>` points to server IP
- Cloudflare proxy disabled (DNS-only mode, "grey cloud") to allow direct TLS termination at Caddy and avoid layer-7 caching issues with WebSocket and streaming services
- API token scoped to `Zone:DNS:Edit` on the specific zone, used by Caddy for DNS-01 ACME challenges

## 6. Authentication

### Decision: Native auth per service, no SSO

Each service handles its own authentication. There is no central identity provider or SSO layer.

### Rationale

At the current service count (2 active stacks), the complexity of running a separate identity provider (Authelia, Authentik, Keycloak) is not justified. Each service has one or two users; the friction of separate logins is negligible. Self-registration is disabled on all public-facing services.

Services requiring isolation (Vaultwarden, if added) benefit from being independent of any identity provider — the password manager must be accessible even if other services are broken.

### Revisit Criteria

Add an identity provider if: (a) service count exceeds ~8 and cross-service login friction is a real daily problem, or (b) a service with no usable native auth is added. Authelia (~50MB RAM, SQLite) or Pocket-ID (passkey-only) are the candidates at that point.

### Alternatives Rejected

**Authelia**: Used in an earlier iteration. Removed because it added significant operational surface (configuration, TOTP setup, OIDC client registration per service, users database management) for a benefit that does not exist at the current scale.

**Authentik**: Heavier (Postgres + Redis + worker, ~500MB RAM). Same objection as Authelia at higher resource cost.

**Keycloak**: Enterprise-grade, far more complex than needed.

## 7. Secrets Management

### Decision: SOPS-encrypted .env files in Git (age backend)

Each stack has a `.env.sops` file committed to the repository. It is a dotenv-format file encrypted with SOPS using an age key. The age public key is in `.sops.yaml` (safe to commit). The age private key lives only on the server (`/root/.config/sops/age/keys.txt`) and in the physical recovery envelope.

### Pattern

- `.env.sops` files are encrypted with: `sops --encrypt --input-type dotenv --output-type dotenv .env > .env.sops`
- `scripts/deploy.sh` decrypts automatically before each deploy: `sops --decrypt --input-type dotenv --output-type dotenv .env.sops > .env`
- `.env` (decrypted) is gitignored; only `.env.sops` is committed
- `.env.example` in each stack provides working local defaults (`*.localhost` URLs, relaxed settings) — `cp .env.example .env` gives a runnable local stack without any secrets
- To update a secret: edit `.env`, re-encrypt to `.env.sops`, commit

### Rationale

Keeping encrypted secrets in Git means the repo is the complete source of truth: a fresh server needs only the age private key and a `git clone` to be fully operational. This simplifies disaster recovery (no separate secrets restore step, no risk of secrets being out of sync with config). The age key is the single secret that must be protected out-of-band.

### Alternatives Considered

**Server-side .env files only**: Simpler initially — no encryption tooling. Rejected because it splits the source of truth: config in Git, secrets in Restic. During recovery, the operator must restore backups before stacks can start. Secrets can silently diverge from the config they belong to.

**HashiCorp Vault**: Industrial strength but requires running another service. Overkill for a single-operator setup.

**Doppler / Infisical**: Good ergonomics but adds an external dependency or another service to maintain.

**Plaintext in Git**: Not acceptable.

## 8. Backup Strategy

### Decision: Restic with 3-2-1 Pattern

- **Primary**: Hetzner Storage Box (1 TB, 4€/month) via SFTP
- **Secondary offsite**: Backblaze B2 (~100-200 GB after deduplication, ~1-2€/month)
- **Local working copy**: Production data on the EX44 itself

This satisfies 3-2-1: three copies (production + Storage Box + B2), two media (Hetzner storage + Backblaze storage), one offsite from primary provider (Backblaze in US, separate from Hetzner EU).

### Backup Mechanics

- **Logical dumps only** for databases: `mongodump`, `pg_dumpall`, SQLite `.backup`. Never backup raw database files directly (consistency risk).
- **Per-stack `backup.sh`** scripts encapsulate each stack's dump logic. Global orchestrator script iterates over stacks.
- **Restic** handles encryption, deduplication, and retention (keep daily 7, weekly 4, monthly 12, yearly 3).
- **Daily backup at 03:00 UTC** via cron.
- **Append-only mode** on Storage Box (ransomware mitigation): a separate host (or manual operation) handles `restic prune`.

### Restore Testing

- **Monthly automated**: restore latest snapshot to temp directory, verify dumps exist and are non-trivial, run a Postgres restore test in a disposable container.
- **Annual full**: provision a Hetzner Cloud CX22, execute the full disaster recovery procedure, verify all services come up, destroy the test VM.

### Why Not Backup Raw Volume Data

PostgreSQL and MongoDB do not guarantee filesystem consistency at any given moment. Restoring from a raw filesystem snapshot taken during writes results in corrupted databases. Logical dumps (taken via the database's native tools while the database is running) are always consistent and portable across major versions.

## 9. Services (Initial Deployment)

Services are added incrementally: test environment first, then production once stable.

### Active

1. **Caddy** — TLS termination, ingress, reverse proxy (caddy-docker-proxy for label-based routing)
2. **Open WebUI** — AI chat interface (Anthropic, OpenAI APIs; native auth, no SSO)

### Planned (Tier 1)

3. **Vaultwarden** — password manager (native auth, deliberately no SSO)
4. **Immich + Postgres + Redis + ML** — photo library
5. **SearXNG** — meta search engine
6. **Uptime Kuma** — service monitoring

### Planned (Tier 2, educational)

7. **Kiwix** — offline Wikipedia (IT/EN), Khan Academy, Project Gutenberg
8. **Audiobookshelf** — audiobooks and podcasts
9. **Forgejo** — private Git

### Optional (Tier 3, only if justified by real need)

10. **Nextcloud** — file sharing
11. **Jellyfin** — media library

### Deliberately Excluded

- **SSO / Identity provider (Authelia, Authentik, Keycloak)**: Added unnecessary complexity for the service count. Each service uses its own native auth. Revisit only if service count grows significantly and cross-service login friction becomes a real problem.
- **LibreChat**: Replaced by Open WebUI, which covers the same use case with a simpler stack (no MongoDB, no Meilisearch, no separate RAG service).
- **Self-hosted email**: deliverability is a continuous battle; professional providers solve this better.
- **Matrix Synapse, Mastodon, Pixelfed**: federation complexity not justified at this scale.

## 10. AI Access (LibreChat)

### Strategy

LibreChat serves as the interface to commercial LLM APIs (Anthropic, OpenAI). Each user has their own Authelia account; LibreChat sessions are tied to those accounts. Conversation history stays in the local MongoDB.

### Configuration

- API keys configured with opt-out from training where available (Anthropic API default, OpenAI Data Controls)
- `ALLOW_REGISTRATION=false`: no self-registration
- `ALLOW_EMAIL_LOGIN=false`, OIDC only via Authelia
- No persistent cross-conversation memory (LibreChat does not implement this by default)

## 11. Domain and Naming

### Decision: Single domain `askalotl.net`

A single domain hosts all services as subdomains: `chat.askalotl.net`, `auth.askalotl.net`, `photos.askalotl.net`, etc. Wildcard certificate via Let's Encrypt.

### Naming Criteria

- Short (≤ 10 characters before TLD)
- Not associated with brands or trademark risks
- Available at standard pricing (≤ 15€/year)


### Registrar: Porkbun

- Low cost, no upsell, free WHOIS privacy
- Solid API for automation
- Decent DNS hosting (though Cloudflare is used as DNS provider for ACME DNS-01)

## 12. Monitoring and Alerting

### Decision: Minimal Stack

- **Uptime Kuma** for service health (HTTP checks, certificate expiry monitoring)
- **External monitoring**: a free service like uptimerobot.com or a small monitoring host elsewhere (potentially a Raspberry Pi at home with Tailscale) to detect when the Hetzner server itself is down (self-monitoring cannot detect this)
- **Alerting**: Telegram bot to operator's phone for service down events

### Explicitly Not Included Initially

Full Prometheus + Grafana + Loki + Alertmanager stack is not deployed initially. The operational complexity is not justified at this scale. Uptime Kuma covers the high-value alerts (service availability, certificate expiry). Logs are inspected via `docker logs` when needed.

If patterns emerge that require deeper observability (frequent issues, performance problems), a lightweight Grafana stack can be added later. Premature observability infrastructure becomes another thing to maintain.

## 13. Deployment Workflow

### Initial Deployment

1. Order Hetzner EX44, install Debian 13 via installimage with RAID1 software, custom partitioning (`/`, `/var/lib/docker`, `/srv/data` separate)
2. Run `bootstrap.sh` as root: user creation, SSH hardening, firewall (ufw + ufw-docker), fail2ban, sysctl, Docker CE, `proxy` network, repo clone
   ```bash
   make bootstrap ENV=test REPO_URL=https://github.com/user/infra-me.git
   ```
3. Copy age private key to server: `/root/.config/sops/age/keys.txt` (mode 600)
4. Deploy stacks:
   ```bash
   make deploy ENV=test
   ```
5. Update DNS to point to server
6. Verify each service end-to-end

### Ongoing Deployments

- Configuration changes: edit files in repo, commit, push, `make deploy`
- Service updates: bump image tags in compose files, `make deploy-<stack>`
- Secret changes: edit `.env`, re-encrypt to `.env.sops`, commit, `make deploy-<stack>`
- Schedule: monthly review of available updates, applied on a planned maintenance window

### Testing

A separate Hetzner Cloud CX22 (4€/month, destroyed after use) serves as the test environment during initial development. The full repo targets the test VPS first. Only after the entire flow works end-to-end on the test VPS does the operator provision production. This minimises paid time on the production server and validates the disaster recovery procedure simultaneously.

## 14. Disaster Recovery

### Recovery Time Objective (RTO): 4-6 hours

Acceptable for this workload. No real-time failover required.

### Recovery Point Objective (RPO): 24 hours

Daily backups are sufficient. Critical data (Vaultwarden) is small and dumped daily; loss of 24 hours of password manager changes is recoverable (users would re-set recently changed passwords).

### Procedure (Summary)

The full procedure lives in `DISASTER_RECOVERY.md`. High-level:

1. Provision new Hetzner server (Debian 13)
2. Restore age private key and restic credentials from physical envelope
3. Run `bootstrap.sh` (clones the repo, installs Docker, hardens the server)
4. Copy age private key to `/root/.config/sops/age/keys.txt`
5. Run `make deploy` — deploy.sh decrypts secrets and starts all stacks
6. Restore database dumps from Restic into each stack's staging directory, replay via each stack's restore procedure
7. Update DNS to new server IP
8. Verify functionally
9. Resume backup schedule

### Critical Off-Server Recovery Materials

Physical sealed envelope in a safe location contains:
- **age private key** (decrypts all `.env.sops` files in the repo)
- Restic password
- Hetzner Robot account recovery codes
- Cloudflare account 2FA recovery codes
- Backblaze B2 application keys
- GitHub account 2FA recovery codes
- Operator's printed copy of `DISASTER_RECOVERY.md`

Without the age private key, no stack can start (all secrets are encrypted). Without these materials, full recovery is impossible. Their existence and accuracy is the single most important piece of operational hygiene.

## 15. Cost Estimate

| Item | Monthly | Annual |
|---|---|---|
| Hetzner EX44 dedicated | 44€ | 528€ |
| Hetzner Setup fee (one-time, year 1) | — | ~79€ |
| Hetzner Storage Box BX11 (1 TB) | 4€ | 48€ |
| Backblaze B2 (estimated) | ~1-2€ | ~18€ |
| Domain (Porkbun) | ~1€ | 12€ |
| LLM API usage (estimated) | ~10-20€ | 120-240€ |
| **Total annual (year 1)** | | **~810-930€** |
| **Total annual (year 2+)** | | **~730-850€** |

3-year TCO: approximately 2,300-2,650€ depending on API usage.

This is intentionally not optimized for minimum cost. The alternative would be commercial services at similar or higher cost, or home-hosted at lower cost but with reliability compromises.

## 16. Operational Principles

These principles guide ongoing decisions:

**Boring infrastructure**: prefer mature, well-understood tools over novel ones. The homelab is not a research project.

**Configuration as code**: every change should be visible in Git. The server has no state that cannot be reconstructed from the repo + restic backups.

**Minimum viable security**: SSH key auth, no root login, firewall, fail2ban, unattended security upgrades, services behind Authelia. Not paranoid hardening that creates operational friction.

**Backup early, restore-test always**: a backup that has never been restored is a hope, not a backup.

**Reversibility**: every choice should have a documented rollback or migration path. No vendor lock-in deeper than the choice of Hetzner as physical host, which is itself replaceable by any provider with similar offering.

## 17. Future Evolution

Possible future additions are noted here so they are not forgotten, but not committed to.

- **Home backup target**: a small mini-PC or NAS at the operator's home, accessed via Tailscale, serving as a true geographic offsite backup (currently Backblaze in US satisfies this)
- **Local LLM inference**: a Mac mini or GPU host at home if commercial AI providers become unacceptable or local model quality reaches parity
- **Second site**: an additional Hetzner Cloud VPS at a different datacenter for critical service redundancy (e.g., Vaultwarden replica)
- **K3s migration**: if the service count grows significantly (20+) and orchestration value increases, migrate to K3s with Argo CD for true GitOps

These are explicitly deferred. The system as designed is sufficient for the stated goals and will remain so for years.

## 18. Document Maintenance

This document is the source of truth for *why* the infrastructure looks the way it does. When making future changes:

- If a decision recorded here is reversed, update this document with the new decision and the reasoning
- If a new service is added, add it under section 9 with the rationale for inclusion
- Annual review: read through and confirm decisions still apply; update where context has changed

The goal is that anyone (including the operator in five years) can read this document and understand both the current state and the reasoning, without needing to reconstruct it.
