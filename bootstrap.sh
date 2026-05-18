#!/usr/bin/env bash
# First-run server bootstrap. Runs as root on the target machine.
# Usage: bash bootstrap.sh <git-clone-url>
#   or:  REPO_URL=<url> bash bootstrap.sh
set -euo pipefail

REPO_URL="${REPO_URL:-${1:-}}"
REPO_PATH="${REPO_PATH:-/opt/infra}"
SSH_USER="${SSH_USER:-fabri}"
TIMEZONE="${TIMEZONE:-Europe/Rome}"
SOPS_VERSION="3.9.4"

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

step() { echo; echo "── $*"; }

# ── System ────────────────────────────────────────────────────────────────────

step "Timezone"
timedatectl set-timezone "$TIMEZONE"

step "Base packages"
apt-get update -qq
apt-get install -y --no-install-recommends \
  vim git curl wget jq htop \
  unattended-upgrades apt-transport-https \
  ca-certificates gnupg ufw fail2ban age

step "Unattended upgrades"
systemctl enable --now unattended-upgrades

# ── User ──────────────────────────────────────────────────────────────────────

step "User: ${SSH_USER}"
if ! id "$SSH_USER" &>/dev/null; then
  useradd -m -s /bin/bash -G sudo "$SSH_USER"
fi
echo "${SSH_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${SSH_USER}"
chmod 0440 "/etc/sudoers.d/${SSH_USER}"

# Copy root's authorized_keys → fabri (server must have root SSH key from Hetzner setup)
install -d -m 700 -o "$SSH_USER" -g "$SSH_USER" "/home/${SSH_USER}/.ssh"
if [[ -f /root/.ssh/authorized_keys ]]; then
  cp /root/.ssh/authorized_keys "/home/${SSH_USER}/.ssh/authorized_keys"
  chown "${SSH_USER}:${SSH_USER}" "/home/${SSH_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${SSH_USER}/.ssh/authorized_keys"
fi

# ── SSH hardening ─────────────────────────────────────────────────────────────

step "SSH hardening"
sshd_conf=/etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_conf"
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_conf"
sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$sshd_conf"
sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$sshd_conf"
sshd -t && systemctl restart sshd

# ── Sysctl hardening ──────────────────────────────────────────────────────────

step "Sysctl"
cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
EOF
sysctl --system -q

# ── Firewall ──────────────────────────────────────────────────────────────────

step "UFW"
# Stop conflicting services
systemctl stop nftables 2>/dev/null || true
systemctl disable nftables 2>/dev/null || true

# ufw-docker: prevents Docker from punching holes in UFW rules
curl -fsSL https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker \
  -o /usr/local/bin/ufw-docker
chmod +x /usr/local/bin/ufw-docker

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp

# Install ufw-docker rules (must be done after UFW is configured, before enable)
ufw-docker install
ufw-docker install-service --force

ufw --force enable
ufw-docker check

# ── Fail2ban ──────────────────────────────────────────────────────────────────

step "Fail2ban"
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 10m
findtime = 1h
maxretry = 5
banaction = ufw

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
EOF
systemctl enable --now fail2ban

# ── SOPS ──────────────────────────────────────────────────────────────────────

step "SOPS v${SOPS_VERSION}"
if ! command -v sops &>/dev/null; then
  curl -fsSL "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64" \
    -o /usr/local/bin/sops
  chmod +x /usr/local/bin/sops
fi

# ── Docker ────────────────────────────────────────────────────────────────────

step "Docker CE"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

DIST=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian ${DIST} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

usermod -aG docker "$SSH_USER"
systemctl enable --now docker

step "Docker network: proxy"
docker network inspect proxy &>/dev/null || docker network create proxy

# ── Clone repo ────────────────────────────────────────────────────────────────

if [[ -n "$REPO_URL" ]]; then
  step "Clone repo → ${REPO_PATH}"
  if [[ -d "${REPO_PATH}/.git" ]]; then
    echo "Repo already exists, pulling latest"
    git -C "$REPO_PATH" pull
  else
    git clone "$REPO_URL" "$REPO_PATH"
  fi
  chown -R "${SSH_USER}:${SSH_USER}" "$REPO_PATH"
else
  echo ""
  echo "⚠ REPO_URL not set — skipping clone. After setting up credentials:"
  echo "  git clone <url> ${REPO_PATH}"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "✓ Bootstrap complete."
echo ""
echo "Next steps:"
echo "  1. Install age private key:"
echo "       mkdir -p /root/.config/sops/age"
echo "       # copy age private key to /root/.config/sops/age/keys.txt"
echo "       chmod 600 /root/.config/sops/age/keys.txt"
echo "  2. Deploy stacks:"
echo "       cd ${REPO_PATH} && ./scripts/deploy.sh"
