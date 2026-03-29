#!/usr/bin/env bash

set -euo pipefail

VM_HOST="${1:-${VM_HOST:-}}"
ADMIN_USER="${ADMIN_USER:-azureuser}"

if [[ -z "$VM_HOST" ]]; then
  echo "Usage: $0 <vm-host-or-ip>" >&2
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "Missing required command: ssh" >&2
  exit 1
fi

ssh -o StrictHostKeyChecking=accept-new "${ADMIN_USER}@${VM_HOST}" <<'EOF'
set -euo pipefail

sudo apt-get update
sudo apt-get install -y ca-certificates curl git gnupg jq openssl rsync cron

sudo install -m 0755 -d /etc/apt/keyrings

if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi

source /etc/os-release
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker
sudo systemctl enable --now cron
sudo usermod -aG docker "$USER"

sudo install -d -m 0755 /opt/documenso /opt/documenso/app /opt/documenso/backups /opt/documenso/bin
sudo chown -R "$USER":"$USER" /opt/documenso
EOF

echo "Bootstrapped ${VM_HOST}"
