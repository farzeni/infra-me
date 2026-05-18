# infra-me

Self-hosted infrastructure on a single Hetzner dedicated server, managed via Docker Compose and shell scripts.

## Structure

```
stacks/                    # One directory per service stack
  caddy/
  openwebui/
  ...                      # each stack: compose.yaml, .env.example, .env.sops, backup.sh
bootstrap.sh               # One-time server setup (run as root)
run.sh                     # Start stacks locally or in production
scripts/
  test-server.sh           # Create/destroy Hetzner test server
  install-deps.sh          # Install hcloud CLI on laptop
Makefile                   # Remote deploy triggers via SSH
.sops.yaml                 # SOPS age key config
docs/
  DESIGN.md
```

## Local dev

```bash
./run.sh local all
./run.sh local caddy openwebui
./run.sh status
```

On first run, `.env.example` is copied to `.env` automatically. Services are available at `https://*.localhost` (Caddy uses a local self-signed CA — trust it once with `caddy trust`).

## Test server

```bash
./scripts/install-deps.sh          # install hcloud CLI (once)
./scripts/test-server.sh up        # create CX22 test server
./scripts/test-server.sh down      # destroy it
```

Update `TEST_HOST` in `Makefile` with the printed IP after `up`.

## Bootstrap

Run once on a fresh server:

```bash
make bootstrap ENV=test REPO_URL=https://github.com/user/infra-me.git
```

Covers: timezone, base packages, `fabri` user, SSH hardening, sysctl, UFW (22/80/443), fail2ban, Docker CE, `proxy` network, repo clone.

After bootstrap, copy the age private key to the server:

```bash
scp /path/to/age-key.txt root@<host>:/root/.config/sops/age/keys.txt
```

## Secrets

Secrets live in `.env.sops` files — dotenv format, encrypted with SOPS (age backend), committed to Git. The age public key is in `.sops.yaml`.

```bash
# Create or update a secret:
cd stacks/<stack>
cp .env.example .env
vim .env                  # fill in real values
sops --encrypt --input-type dotenv --output-type dotenv .env > .env.sops
git add .env.sops && git commit

# Generate age key pair (once, store private key off-server):
age-keygen -o keys.txt    # public key → paste into .sops.yaml
```

## Deploy

```bash
# Deploy all stacks to test
make deploy

# Deploy specific stacks
make deploy-caddy
make deploy-openwebui ENV=prod

# Status
make status
make status ENV=prod
```

`make deploy` SSHes into the server, pulls the latest Git commit, then runs `./run.sh prod` which decrypts `.env.sops → .env` and does `docker compose up`.

## Servers

| Name | ENV | Host |
|------|-----|------|
| infra-test | test | 46.225.170.110 |
| infra-prod | prod | TBD |
