#!/usr/bin/env bash
set -euo pipefail

# Install operator tooling on the laptop (Debian/Ubuntu)

HCLOUD_VERSION="1.64.1"
ARCH="$(dpkg --print-architecture)"  # amd64 or arm64

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

install_hcloud
