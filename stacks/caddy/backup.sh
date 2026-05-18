#!/usr/bin/env bash
# Backup script for Caddy stack.
# Backs up the caddy_data volume (TLS certs). Certs can be re-issued but backup
# avoids Let's Encrypt rate limits on recovery.
set -euo pipefail

STACK_NAME="caddy"
BACKUP_DIR="${1:?Usage: $0 <backup-staging-dir>}"
TARGET_DIR="${BACKUP_DIR}/${STACK_NAME}"

mkdir -p "${TARGET_DIR}"

if docker volume inspect caddy_data &>/dev/null; then
  docker run --rm \
    -v caddy_data:/data:ro \
    -v "${TARGET_DIR}:/backup" \
    busybox tar czf /backup/caddy_data.tar.gz /data
else
  echo "Warning: caddy_data volume not found, skipping cert backup" >&2
fi

echo "${STACK_NAME} backup complete to ${TARGET_DIR}"
