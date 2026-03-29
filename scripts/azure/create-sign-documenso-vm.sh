#!/usr/bin/env bash

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-sign-documenso-rg}"
LOCATION="${LOCATION:-westus3}"
VM_NAME="${VM_NAME:-sign-documenso-vm}"
ADMIN_USER="${ADMIN_USER:-azureuser}"
VM_SIZE="${VM_SIZE:-Standard_B2ms}"
OS_DISK_SIZE_GB="${OS_DISK_SIZE_GB:-64}"
STORAGE_SKU="${STORAGE_SKU:-StandardSSD_LRS}"
VNET_NAME="${VNET_NAME:-${VM_NAME}-vnet}"
SUBNET_NAME="${SUBNET_NAME:-${VM_NAME}-subnet}"
NSG_NAME="${NSG_NAME:-${VM_NAME}-nsg}"
PIP_NAME="${PIP_NAME:-${VM_NAME}-pip}"
NIC_NAME="${NIC_NAME:-${VM_NAME}-nic}"
ADDRESS_PREFIX="${ADDRESS_PREFIX:-10.32.0.0/16}"
SUBNET_PREFIX="${SUBNET_PREFIX:-10.32.1.0/24}"
SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH:-${HOME}/.ssh/id_ed25519.pub}"
SSH_SOURCE_CIDR="${SSH_SOURCE_CIDR:-}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command az
require_command curl

if [[ ! -f "$SSH_PUBLIC_KEY_PATH" ]]; then
  SSH_PUBLIC_KEY_PATH="${HOME}/.ssh/id_rsa.pub"
fi

if [[ ! -f "$SSH_PUBLIC_KEY_PATH" ]]; then
  echo "No SSH public key found. Set SSH_PUBLIC_KEY_PATH to a valid .pub file." >&2
  exit 1
fi

if [[ -z "$SSH_SOURCE_CIDR" ]]; then
  SSH_SOURCE_CIDR="$(curl -4fsSL https://ifconfig.me)/32"
fi

SSH_PUBLIC_KEY="$(<"$SSH_PUBLIC_KEY_PATH")"

az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none

az network vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --address-prefixes "$ADDRESS_PREFIX" \
  --subnet-name "$SUBNET_NAME" \
  --subnet-prefixes "$SUBNET_PREFIX" \
  --output none

az network public-ip create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PIP_NAME" \
  --sku Standard \
  --allocation-method Static \
  --output none

az network nsg create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$NSG_NAME" \
  --output none

az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  --name AllowHttps \
  --priority 100 \
  --access Allow \
  --direction Inbound \
  --protocol Tcp \
  --source-address-prefixes '*' \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 443 \
  --output none

az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  --name AllowHttp \
  --priority 110 \
  --access Allow \
  --direction Inbound \
  --protocol Tcp \
  --source-address-prefixes '*' \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 80 \
  --output none

az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  --name AllowSshFromOperator \
  --priority 120 \
  --access Allow \
  --direction Inbound \
  --protocol Tcp \
  --source-address-prefixes "$SSH_SOURCE_CIDR" \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22 \
  --output none

az network nic create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$NIC_NAME" \
  --vnet-name "$VNET_NAME" \
  --subnet "$SUBNET_NAME" \
  --network-security-group "$NSG_NAME" \
  --public-ip-address "$PIP_NAME" \
  --output none

az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --nics "$NIC_NAME" \
  --image Ubuntu2204 \
  --size "$VM_SIZE" \
  --admin-username "$ADMIN_USER" \
  --ssh-key-values "$SSH_PUBLIC_KEY" \
  --os-disk-size-gb "$OS_DISK_SIZE_GB" \
  --storage-sku "$STORAGE_SKU" \
  --output none

VM_PUBLIC_IP="$(az network public-ip show --resource-group "$RESOURCE_GROUP" --name "$PIP_NAME" --query ipAddress --output tsv)"

echo "VM_NAME=$VM_NAME"
echo "VM_PUBLIC_IP=$VM_PUBLIC_IP"
echo "SSH_TARGET=${ADMIN_USER}@${VM_PUBLIC_IP}"
