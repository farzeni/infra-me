#!/usr/bin/env bash
set -euo pipefail

# Install SOPS and age on the operator's laptop (Debian/Ubuntu)
# Run as a regular user with sudo access.

SOPS_VERSION="3.13.1"
AGE_VERSION="1.1.1"
HCLOUD_VERSION="1.64.1"
ARCH="$(dpkg --print-architecture)"  # amd64 or arm64

install_age() {
  if command -v age &>/dev/null; then
    echo "age already installed: $(age --version)"
    return
  fi
  echo "Installing age ${AGE_VERSION}..."
  sudo apt-get install -y age
  echo "age installed: $(age --version)"
}

install_sops() {
  if command -v sops &>/dev/null; then
    local current
    current="$(sops --version 2>&1 | awk '{print $2}')"
    echo "sops already installed: ${current}"
    return
  fi
  echo "Installing sops ${SOPS_VERSION}..."

  local url="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops_${SOPS_VERSION}_${ARCH}.deb"
  local tmp
  tmp="$(mktemp --suffix=.deb)"
  wget -qO "${tmp}" "${url}"
  sudo dpkg -i "${tmp}"
  rm -f "${tmp}"
  echo "sops installed: $(sops --version)"
}

install_hcloud() {
  if command -v hcloud &>/dev/null; then
    echo "hcloud already installed: $(hcloud version)"
    return
  fi
  echo "Installing hcloud ${HCLOUD_VERSION}..."
  local url="https://github.com/hetznercloud/cli/releases/download/v${HCLOUD_VERSION}/hcloud-cli_${HCLOUD_VERSION}_${ARCH}.deb"
  local tmp
  tmp="$(mktemp --suffix=.deb)"
  wget -qO "${tmp}" "${url}"
  sudo dpkg -i "${tmp}"
  rm -f "${tmp}"
  echo "hcloud installed: $(hcloud version)"
}

install_age
install_sops
install_hcloud

# Generate an age key if one doesn't exist yet
AGE_KEY_DIR="${HOME}/.config/sops/age"
AGE_KEY_FILE="${AGE_KEY_DIR}/keys.txt"

if [[ -f "${AGE_KEY_FILE}" ]]; then
  echo "age key already exists at ${AGE_KEY_FILE}"
else
  echo "Generating age key..."
  mkdir -p "${AGE_KEY_DIR}"
  chmod 700 "${AGE_KEY_DIR}"
  age-keygen -o "${AGE_KEY_FILE}"
  chmod 600 "${AGE_KEY_FILE}"
  echo ""
  echo "IMPORTANT: Back up ${AGE_KEY_FILE} to a secure location (paper copy, offline storage)."
  echo "Losing this key means losing access to all encrypted secrets."
fi

echo ""
echo "Your age public key (add this to .sops.yaml):"
grep "public key" "${AGE_KEY_FILE}" | awk '{print $NF}'
