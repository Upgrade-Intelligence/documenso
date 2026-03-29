#!/usr/bin/env bash

set -euo pipefail

HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-Z02923672NWN2NPK2I3X8}"
RECORD_NAME="${RECORD_NAME:-sign.tomoai.io}"
IP_ADDRESS="${IP_ADDRESS:-}"
TTL="${TTL:-300}"

if [[ -z "$IP_ADDRESS" ]]; then
  echo "Set IP_ADDRESS to the Azure VM public IP." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "Missing required command: aws" >&2
  exit 1
fi

change_batch="$(mktemp)"

cat >"$change_batch" <<EOF
{
  "Comment": "Point ${RECORD_NAME} to the Documenso Azure VM",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${RECORD_NAME}",
        "Type": "A",
        "TTL": ${TTL},
        "ResourceRecords": [
          { "Value": "${IP_ADDRESS}" }
        ]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch "file://$change_batch" >/dev/null

rm -f "$change_batch"

echo "Updated ${RECORD_NAME} -> ${IP_ADDRESS}"
