# infra-me

Self-hosted infrastructure on a single Hetzner dedicated server, managed via Ansible and Docker Compose.

## Index

- [Bootstrap](#bootstrap)

## Summary

This repository contains the Ansible playbooks and roles for provisioning and managing the infrastructure stack. Each server goes through two phases:

- **Bootstrap**: One-time server initialization (user setup, SSH hardening, Docker, firewall, fail2ban)
- **Deploy**: Ongoing service deployment (stacks, secrets, containers)

Both test and production servers use the same playbooks — target via `--limit`.

## Bootstrap

Run once on a fresh server to provision the base system.

### Prerequisites

Create the test server via `test-server.sh` — this also syncs the IP into the Ansible inventory:

```bash
./scripts/test-server.sh up    # creates server, updates inventory
./scripts/test-server.sh down  # deletes server, resets inventory to TBD
```

```bash
# Bootstrap all servers
ansible-playbook bootstrap.yaml

# Bootstrap test server only
ansible-playbook bootstrap.yaml --limit infra-test

# Bootstrap production server only
ansible-playbook bootstrap.yaml --limit infra-prod

# Run specific roles only
ansible-playbook bootstrap.yaml --limit infra-test --tags server_setup
ansible-playbook bootstrap.yaml --limit infra-test --tags docker
ansible-playbook bootstrap.yaml --limit infra-test --tags security

# Dry run (check mode)
ansible-playbook bootstrap.yaml --limit infra-test --check --diff
```

### What bootstrap does

| Role | Tasks |
|------|-------|
| `server_setup` | Timezone, base packages, unattended-upgrades, `fabri` user + NOPASSWD sudo, SSH key auth, SSH hardening, sysctl tuning |
| `docker` | Docker CE + compose-plugin, `proxy` network, `fabri` in docker group |
| `security` | UFW (allow 22/80/443), fail2ban SSH jail |

## Deploy

Ongoing service deployments (populated as stacks are built).

```bash
ansible-playbook deploy.yaml --limit infra-test
```

## Inventory

| Server | Group | Status |
|--------|-------|--------|
| `infra-test` | test | Active |
| `infra-prod` | production | Pending |

## Structure

```
scripts/
├── test-server.sh         # Create/destroy test server, syncs IP to inventory
└── install-deps.sh        # Install SOPS, age, hcloud CLI
ansible/
├── ansible.cfg
├── bootstrap.yaml
├── deploy.yaml
├── inventory/
│   ├── hosts.yaml
│   └── group_vars/
│       ├── all.yaml
│       ├── test.yaml
│       └── production.yaml
└── roles/
    ├── server_setup/
    ├── docker/
    ├── security/
    └── deploy/
```
