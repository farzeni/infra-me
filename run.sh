#!/usr/bin/env bash
# Stack runner for local dev and production.
#
# Usage:
#   ./run.sh local [all | stack ...]    # copy .env.example → .env, then up
#   ./run.sh prod  [all | stack ...]    # sops decrypt .env.sops → .env, then up
#   ./run.sh status                     # show running containers across all stacks
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="${REPO_ROOT}/stacks"
DEFAULT_ORDER=(caddy openwebui)

usage() {
  echo "Usage: $0 local [all | stack ...]"
  echo "       $0 prod  [all | stack ...]"
  echo "       $0 status"
  echo ""
  echo "Available stacks: $(ls "${STACKS_DIR}" | tr '\n' ' ')"
  exit 1
}

[[ $# -eq 0 ]] && usage

MODE="$1"; shift

# ── Status ────────────────────────────────────────────────────────────────────

if [[ "$MODE" == "status" ]]; then
  for d in "${STACKS_DIR}"/*/; do
    echo "=== $(basename "$d") ==="
    docker compose -f "${d}compose.yaml" ps --format table 2>/dev/null || true
  done
  exit 0
fi

[[ "$MODE" == "local" || "$MODE" == "prod" ]] || usage
[[ $# -eq 0 ]] && usage

# ── Resolve stack list ────────────────────────────────────────────────────────

if [[ "$1" == "all" ]]; then
  STACKS=("${DEFAULT_ORDER[@]}")
else
  STACKS=("$@")
fi

# ── Prerequisites ─────────────────────────────────────────────────────────────

if ! docker network inspect proxy &>/dev/null; then
  echo "Creating Docker network: proxy"
  docker network create proxy
fi

# ── Prepare .env for a stack ──────────────────────────────────────────────────

prepare_env() {
  local stack_dir="$1"

  if [[ "$MODE" == "prod" ]]; then
    if [[ -f "${stack_dir}/.env.sops" ]]; then
      sops --decrypt --input-type dotenv --output-type dotenv \
        "${stack_dir}/.env.sops" > "${stack_dir}/.env"
      chmod 600 "${stack_dir}/.env"
    else
      echo "  WARNING: no .env.sops found, skipping decrypt"
    fi
  else
    if [[ ! -f "${stack_dir}/.env" ]]; then
      if [[ -f "${stack_dir}/.env.example" ]]; then
        echo "  .env not found — copying from .env.example"
        cp "${stack_dir}/.env.example" "${stack_dir}/.env"
      else
        echo "  WARNING: no .env or .env.example found"
      fi
    fi
  fi
}

# ── Start stacks ──────────────────────────────────────────────────────────────

for stack in "${STACKS[@]}"; do
  stack_dir="${STACKS_DIR}/${stack}"

  if [[ ! -d "$stack_dir" ]]; then
    echo "ERROR: unknown stack '${stack}'" >&2
    echo "Available: $(ls "${STACKS_DIR}" | tr '\n' ' ')" >&2
    exit 1
  fi

  echo ""
  echo "▶ ${stack} [${MODE}]"

  prepare_env "$stack_dir"

  docker compose -f "${stack_dir}/compose.yaml" up -d --wait --remove-orphans
done

echo ""
echo "✓ done"
