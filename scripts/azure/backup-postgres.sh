#!/usr/bin/env bash

set -euo pipefail

REMOTE_ROOT="${REMOTE_ROOT:-/opt/documenso}"
APP_DIR="${APP_DIR:-${REMOTE_ROOT}/app}"
ENV_FILE="${ENV_FILE:-${REMOTE_ROOT}/.env}"
BACKUP_DIR="${BACKUP_DIR:-${REMOTE_ROOT}/backups}"
PROJECT_NAME="${PROJECT_NAME:-sign-documenso}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

mkdir -p "$BACKUP_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="${BACKUP_DIR}/postgres-${timestamp}.sql.gz"

cd "$APP_DIR"

sudo docker compose \
  --env-file "$ENV_FILE" \
  -f docker/production/compose.yml \
  -f docker/azure/compose.override.yml \
  --project-name "$PROJECT_NAME" \
  exec -T database \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip -9 >"$backup_file"

find "$BACKUP_DIR" -type f -name 'postgres-*.sql.gz' -mtime +7 -delete

echo "Created backup at $backup_file"
