#!/usr/bin/env bash

set -euo pipefail

VM_HOST="${1:-${VM_HOST:-}}"
ENV_FILE="${2:-${ENV_FILE:-}}"
ADMIN_USER="${ADMIN_USER:-azureuser}"
REMOTE_ROOT="${REMOTE_ROOT:-/opt/documenso}"
REMOTE_APP_DIR="${REMOTE_APP_DIR:-${REMOTE_ROOT}/app}"
PROJECT_NAME="${PROJECT_NAME:-sign-documenso}"
CRON_SCHEDULE="${CRON_SCHEDULE:-17 3 * * *}"

if [[ -z "$VM_HOST" || -z "$ENV_FILE" ]]; then
  echo "Usage: $0 <vm-host-or-ip> <env-file>" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

for command_name in rsync scp ssh; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SSH_TARGET="${ADMIN_USER}@${VM_HOST}"

rsync \
  --archive \
  --compress \
  --delete \
  --exclude '.git/' \
  --exclude '.env' \
  --exclude '.turbo/' \
  --exclude 'build.log' \
  --exclude 'node_modules/' \
  -e "ssh -o StrictHostKeyChecking=accept-new" \
  "${REPO_ROOT}/" \
  "${SSH_TARGET}:${REMOTE_APP_DIR}/"

scp -o StrictHostKeyChecking=accept-new "$ENV_FILE" "${SSH_TARGET}:${REMOTE_ROOT}/.env.tmp"

ssh -o StrictHostKeyChecking=accept-new "$SSH_TARGET" \
  "CRON_SCHEDULE='${CRON_SCHEDULE}' REMOTE_ROOT='${REMOTE_ROOT}' REMOTE_APP_DIR='${REMOTE_APP_DIR}' PROJECT_NAME='${PROJECT_NAME}' bash -s" <<'EOF'
set -euo pipefail

sudo install -m 0600 -o "$USER" -g "$USER" "${REMOTE_ROOT}/.env.tmp" "${REMOTE_ROOT}/.env"
rm -f "${REMOTE_ROOT}/.env.tmp"

set -a
source "${REMOTE_ROOT}/.env"
set +a

sudo install -d -m 0755 "${REMOTE_ROOT}/backups" "${REMOTE_ROOT}/bin"
sudo install -m 0755 "${REMOTE_APP_DIR}/scripts/azure/backup-postgres.sh" "${REMOTE_ROOT}/bin/backup-postgres.sh"

if [[ ! -s "${REMOTE_ROOT}/cert.p12" ]]; then
  temp_key="$(mktemp)"
  temp_crt="$(mktemp)"

  openssl req \
    -x509 \
    -nodes \
    -days 3650 \
    -newkey rsa:2048 \
    -keyout "$temp_key" \
    -out "$temp_crt" \
    -subj "/C=US/O=Tomo Sign/CN=${DOCUMENSO_HOSTNAME}"

  openssl pkcs12 \
    -export \
    -out "${REMOTE_ROOT}/cert.p12" \
    -inkey "$temp_key" \
    -in "$temp_crt" \
    -passout "pass:${NEXT_PRIVATE_SIGNING_PASSPHRASE}"

  rm -f "$temp_key" "$temp_crt"
  chmod 0644 "${REMOTE_ROOT}/cert.p12"
fi

sudo tee /etc/cron.d/sign-documenso-backup >/dev/null <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${CRON_SCHEDULE} root ${REMOTE_ROOT}/bin/backup-postgres.sh >> /var/log/sign-documenso-backup.log 2>&1
CRON

sudo systemctl restart cron

cd "${REMOTE_APP_DIR}"

sudo docker compose \
  --env-file "${REMOTE_ROOT}/.env" \
  -f docker/production/compose.yml \
  -f docker/azure/compose.override.yml \
  --project-name "${PROJECT_NAME}" \
  up -d --build
EOF

echo "Deployed to ${VM_HOST}"
