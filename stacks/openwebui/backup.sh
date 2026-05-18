#!/usr/bin/env bash
# Backup script for Open WebUI stack.
# Open WebUI stores its SQLite database and uploads in /app/backend/data.
set -euo pipefail

STACK_NAME="openwebui"
BACKUP_DIR="${1:?Usage: $0 <backup-staging-dir>}"
TARGET_DIR="${BACKUP_DIR}/${STACK_NAME}"

mkdir -p "${TARGET_DIR}"

CONTAINER=$(docker ps --filter "ancestor=ghcr.io/open-webui/open-webui" --format '{{.Names}}' | head -1)

if [[ -n "$CONTAINER" ]]; then
  # SQLite backup via sqlite3 (consistent, avoids WAL race)
  docker exec "$CONTAINER" sh -c \
    'sqlite3 /app/backend/data/webui.db ".backup /tmp/webui-backup.db"' 2>/dev/null || true

  if docker exec "$CONTAINER" test -f /tmp/webui-backup.db 2>/dev/null; then
    docker cp "${CONTAINER}:/tmp/webui-backup.db" "${TARGET_DIR}/webui.db"
    docker exec "$CONTAINER" rm -f /tmp/webui-backup.db
  else
    echo "Warning: sqlite3 backup failed, falling back to raw copy" >&2
    docker cp "${CONTAINER}:/app/backend/data/webui.db" "${TARGET_DIR}/webui.db" 2>/dev/null || true
  fi
else
  echo "Warning: openwebui container not running, skipping backup" >&2
fi

echo "${STACK_NAME} backup complete to ${TARGET_DIR}"
