#!/usr/bin/env bash
set -euo pipefail

SERVER_NAME="infra-test"
SERVER_TYPE="cpx32"
IMAGE="debian-13"
LOCATION="nbg1"
HCLOUD_CONTEXT="infra-me"

export HCLOUD_CONTEXT

# Resolve SSH key name from local default public key fingerprint
resolve_ssh_key() {
  local pubkey fingerprint hcloud_keys
  hcloud_keys="$(hcloud ssh-key list -o noheader -o columns=name,fingerprint)"
  for pubkey in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
    [[ -f "${pubkey}" ]] || continue
    fingerprint="$(ssh-keygen -E md5 -lf "${pubkey}" | awk '{print $2}' | sed 's/^MD5://')"
    local name
    name="$(echo "${hcloud_keys}" | grep -F "${fingerprint}" | awk '{print $1}')"
    if [[ -n "${name}" ]]; then
      echo "${name}"
      return
    fi
  done
  echo ""
}

SSH_KEY="$(resolve_ssh_key)"
if [[ -z "${SSH_KEY}" ]]; then
  echo "Warning: no local default SSH key found in hcloud context '${HCLOUD_CONTEXT}'." >&2
fi

usage() {
  echo "Usage: $0 <up|down>"
  exit 1
}

cmd_up() {
  if hcloud server describe "${SERVER_NAME}" &>/dev/null; then
    echo "Server '${SERVER_NAME}' already exists."
    hcloud server describe "${SERVER_NAME}" | grep -E "ID:|Status:|IPv4:"
    return
  fi

  local args=(
    --name "${SERVER_NAME}"
    --type "${SERVER_TYPE}"
    --image "${IMAGE}"
    --location "${LOCATION}"
  )
  [[ -n "${SSH_KEY}" ]] && args+=(--ssh-key "${SSH_KEY}")

  echo "Creating server '${SERVER_NAME}' (${SERVER_TYPE}, ${IMAGE}, ${LOCATION})..."
  hcloud server create "${args[@]}"

  local server_ip
  server_ip="$(hcloud server describe "${SERVER_NAME}" -o format='{{.PublicNet.IPv4.IP}}')"
  echo ""
  echo "IP: ${server_ip}"
  echo "Update TEST_HOST in Makefile: root@${server_ip}"
}

cmd_down() {
  if ! hcloud server describe "${SERVER_NAME}" &>/dev/null; then
    echo "Server '${SERVER_NAME}' does not exist."
    return
  fi

  echo "Deleting server '${SERVER_NAME}'..."
  hcloud server delete "${SERVER_NAME}"
  echo "Done."
}

[[ $# -ne 1 ]] && usage

case "$1" in
  up)   cmd_up ;;
  down) cmd_down ;;
  *)    usage ;;
esac
