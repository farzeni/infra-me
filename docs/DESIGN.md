# Infrastructure Design Document

This document captures the architectural decisions for this self-hosted infrastructure, including the reasoning behind each choice. It serves as both a reference for the operator and a guide for future evolution.

Last updated: 2026-05-17

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

### Decision: Docker Compose + Ansible + Git (GitOps-style)

The orchestration approach is intentionally simple: Docker Compose files per stack, version controlled in Git, deployed via Ansible. Configuration is the source of truth in Git; the server is execution.

### Alternatives Rejected

**Kubernetes / K3s**: Originally considered (operator has K8s experience and started migration from Swarm). Rejected for this scope because: orchestration value of K8s shines with multiple nodes, autoscaling, rolling deployments — none of which apply to single-host family workload. The complexity tax is not paid back. K8s remains the right choice for the operator's professional work; this is intentionally different.

**Docker Swarm**: Operator's current setup, explicitly unsatisfactory. Maintenance mode by Docker Inc., minimal active development.

**Portainer**: Adds UI but obscures what is happening underneath. Operator prefers direct control.

**Coolify and similar PaaS-on-self-hosted (Dokploy, CapRover)**: Considered seriously. Would accelerate initial setup significantly. Rejected because GitOps purity is a stated value: configuration must live in Git, not in a control plane database. Coolify's hybrid model (some state in UI database) was deemed unsuitable. Decision is to invest more time in setup for clearer long-term operational model.

**Proxmox + VMs**: Considered for environment isolation. Rejected because the server hosts a single family environment; the abstraction layer would add complexity without isolation benefit. Reconsidered only if future use adds heterogeneous workloads (personal projects requiring isolation from family services).

### Pattern

Each stack lives in its own directory under `stacks/`. A stack is self-contained: compose file, secrets template, configuration files, optional backup script. Stacks share a single Docker network `proxy` (externally created) for ingress. Each stack has its own internal network for database/cache traffic, isolated from other stacks.

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

## 6. Authentication and SSO

### Decision: Authelia with OIDC Provider

Authelia handles authentication. It supports password + TOTP (2FA) and acts as OIDC provider for services that support OIDC, eliminating the need for forward-auth in most cases.

### Service Auth Strategy

- **OIDC integration**: LibreChat, Immich, Nextcloud (if added), Forgejo, Hedgedoc
- **Native auth, no SSO**: Vaultwarden (deliberate: must work independently of identity provider for emergency password recovery)
- **No auth (internal only)**: Monitoring dashboards behind a separate hostname not exposed publicly, or accessible via Tailscale only

### User Management

File-based user database in Authelia (`users.yml`), with argon2id password hashes. For a small user base this is more reliable than running LDAP. Users are created by the operator; self-registration is disabled across all services.

### Alternatives Rejected

**Authentik**: More mature OIDC provider, better admin UI. Rejected because heavier (Postgres + Redis + worker + server, ~500MB RAM vs Authelia ~50MB) and overkill for this scale.

**Keycloak**: Enterprise-grade, far more complex than needed.

**Pocket-ID**: Passkey-only, interesting but excludes users who prefer password+TOTP.

**No SSO at all**: Each service with its own auth. Rejected because as the service count grows (10+), the friction of separate accounts becomes a real usability problem.

## 7. Secrets Management

### Decision: SOPS with age

Secrets are encrypted at rest in the Git repository using SOPS with age keys. Only the operator's age private key can decrypt. The private key is stored locally and backed up to physical paper in a sealed envelope.

### Pattern

- `.env.sops.yaml` files exist for each stack, encrypted in Git
- During deployment, Ansible decrypts to `.env` files on the server (gitignored, file mode 600)
- Encrypted YAML keeps keys visible (only values are encrypted), enabling meaningful Git diffs
- Master key file `~/.config/sops/age/keys.txt` on operator's laptop, never committed

### Alternatives Considered

**HashiCorp Vault**: Industrial strength but requires running another service with HA considerations. Overkill.

**External Secrets Operator + cloud KMS**: Requires cloud KMS backend, adds dependency.

**Encrypted .env files (e.g. ansible-vault)**: Ties secrets to Ansible specifically. SOPS is more portable.

**ejson (Shopify)**: Same family as SOPS, less feature-rich, less actively maintained.

**Plaintext + gitignore**: Loses version history of secret changes, no way to share with a co-maintainer.

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

The initial deployment includes services in priority order. Each service is added incrementally during the test phase, then deployed to production once stable.

### Tier 1: Core Services (deploy first)

1. **Caddy** — TLS, ingress, reverse proxy
2. **Authelia + Redis** — authentication and SSO
3. **Vaultwarden** — password manager (independent auth, no SSO)
4. **LibreChat + MongoDB + Meilisearch** — LLM gateway with local conversation history
5. **Immich + Postgres + Redis + ML** — photo library
6. **SearXNG** — meta search engine
7. **Uptime Kuma** — service monitoring

### Tier 2: Educational Services (add within first few months)

8. **Kiwix** — offline Wikipedia (IT/EN), Khan Academy, Project Gutenberg
9. **Hedgedoc** — collaborative markdown notes
10. **Forgejo** — private Git
11. **Audiobookshelf** — audiobooks and podcasts

### Tier 3: Optional (only if justified by real need)

12. **Nextcloud** — file sharing
13. **Jellyfin** — media library
14. **Matrix Synapse** — federated chat

### Explicitly Excluded

- **Self-hosted email**: deliverability is a continuous battle; professional providers (Proton, Tutanota) solve this better
- **Mastodon, Pixelfed, social network self-hosting**: federation complexity and moderation burden not justified at this scale
- **Self-hosted video conferencing**: quality inferior to commercial options

## 10. AI Access (LibreChat)

### Strategy

LibreChat serves as the interface to commercial LLM APIs (Anthropic, OpenAI). Each user has their own Authelia account; LibreChat sessions are tied to those accounts. Conversation history stays in the local MongoDB.

### Configuration

- API keys configured with opt-out from training where available (Anthropic API default, OpenAI Data Controls)
- `ALLOW_REGISTRATION=false`: no self-registration
- `ALLOW_EMAIL_LOGIN=false`, OIDC only via Authelia
- No persistent cross-conversation memory (LibreChat does not implement this by default)

## 11. Domain and Naming

### Decision: Single domain `askalotl.com`

A single domain hosts all services as subdomains: `chat.askalotl.com`, `auth.askalotl.com`, `photos.askalotl.com`, etc. Wildcard certificate via Let's Encrypt.

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
2. Run `bootstrap.sh` (manual first time, automated for subsequent servers): user creation, SSH hardening, firewall (ufw), fail2ban, Docker installation, unattended security upgrades, base packages
3. Provision age key on server
4. Clone `infra/` repo
5. Run Ansible playbook from operator's laptop
6. Update DNS to point to server
7. Verify each service end-to-end

### Ongoing Deployments

- Configuration changes: edit files in `infra/` repo, commit, push, run `ansible-playbook deploy.yaml`
- Service updates: bump image tags in compose files, `ansible-playbook` with pull policy applies new images
- Schedule: monthly review of available updates, applied on a planned maintenance window (typically weekend evening)

### Testing

A separate Hetzner Cloud CX22 (4€/month, destroyed after use) serves as the test environment during initial development. The full repo and Ansible playbook target the test VPS first. Only after the entire flow works end-to-end on the test VPS does the operator order the production EX44 and deploy there. This minimizes paid time on the production server and validates the disaster recovery procedure simultaneously.

## 14. Disaster Recovery

### Recovery Time Objective (RTO): 4-6 hours

Acceptable for this workload. No real-time failover required.

### Recovery Point Objective (RPO): 24 hours

Daily backups are sufficient. Critical data (Vaultwarden) is small and dumped daily; loss of 24 hours of password manager changes is recoverable (users would re-set recently changed passwords).

### Procedure (Summary)

The full procedure lives in `DISASTER_RECOVERY.md`. High-level:

1. Provision new Hetzner server (Debian 13)
2. Restore age key and restic credentials from physical envelope
3. Clone `infra/` repo
4. Run `bootstrap.sh`
5. Restore `/srv/data` and dump directory from Restic
6. Decrypt SOPS files
7. Start stacks: Caddy, Authelia, Vaultwarden first (no DB restore needed for Vaultwarden as it uses SQLite restored with data; Authelia same)
8. Update DNS to new server IP
9. For each database stack: start DB container, restore from dump, start application
10. Verify functionally
11. Resume backup schedule

### Critical Off-Server Recovery Materials

Physical sealed envelope in a safe location contains:
- Age private key (one-time generated, ~70 characters)
- Restic password
- Hetzner Robot account recovery
- Cloudflare account 2FA recovery codes
- Backblaze B2 application keys
- GitHub account 2FA recovery codes
- Operator's printed copy of `DISASTER_RECOVERY.md`

Without these materials, recovery is impossible. Their existence is the single most important piece of operational hygiene.

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
