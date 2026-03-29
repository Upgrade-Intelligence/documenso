#!/usr/bin/env bash

set -euo pipefail

SES_REGION="${SES_REGION:-us-west-2}"
IAM_USER_NAME="${IAM_USER_NAME:-sign-documenso-ses-smtp}"
IAM_POLICY_NAME="${IAM_POLICY_NAME:-AllowSesSmtpSend}"
OUTPUT_FILE="${OUTPUT_FILE:-./.secrets/sign-documenso-ses-smtp.env}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command aws
require_command jq
require_command python3
require_command mkdir

create_user_if_missing() {
  if aws iam get-user --user-name "$IAM_USER_NAME" >/dev/null 2>&1; then
    return
  fi

  aws iam create-user --user-name "$IAM_USER_NAME" >/dev/null
}

put_send_policy() {
  aws iam put-user-policy \
    --user-name "$IAM_USER_NAME" \
    --policy-name "$IAM_POLICY_NAME" \
    --policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Action\": [\"ses:SendRawEmail\"],
          \"Resource\": \"*\"
        }
      ]
    }" >/dev/null
}

create_access_key() {
  local access_key_count

  access_key_count="$(aws iam list-access-keys --user-name "$IAM_USER_NAME" --query 'length(AccessKeyMetadata)' --output text)"

  if [[ "$access_key_count" -ge 2 ]]; then
    echo "IAM user $IAM_USER_NAME already has 2 access keys. Remove one before creating another." >&2
    exit 1
  fi

  aws iam create-access-key --user-name "$IAM_USER_NAME"
}

main() {
  local tmp_json
  local access_key_id
  local secret_access_key
  local smtp_password

  create_user_if_missing
  put_send_policy

  tmp_json="$(mktemp)"

  create_access_key >"$tmp_json"

  access_key_id="$(jq -r '.AccessKey.AccessKeyId' "$tmp_json")"
  secret_access_key="$(jq -r '.AccessKey.SecretAccessKey' "$tmp_json")"

  smtp_password="$(
    python3 - "$secret_access_key" "$SES_REGION" <<'PY'
import base64
import hashlib
import hmac
import sys

secret_access_key = sys.argv[1]
region = sys.argv[2]

date = "11111111"
service = "ses"
message = "SendRawEmail"
terminal = "aws4_request"
version = 0x04

signature = hmac.new(
    ("AWS4" + secret_access_key).encode("utf-8"),
    date.encode("utf-8"),
    hashlib.sha256,
).digest()
signature = hmac.new(signature, region.encode("utf-8"), hashlib.sha256).digest()
signature = hmac.new(signature, service.encode("utf-8"), hashlib.sha256).digest()
signature = hmac.new(signature, terminal.encode("utf-8"), hashlib.sha256).digest()
signature = hmac.new(signature, message.encode("utf-8"), hashlib.sha256).digest()

smtp_password = base64.b64encode(bytes([version]) + signature).decode("utf-8")
print(smtp_password)
PY
  )"

  mkdir -p "$(dirname "$OUTPUT_FILE")"
  umask 177
  {
    echo "SES_REGION=$SES_REGION"
    echo "NEXT_PRIVATE_SMTP_TRANSPORT=smtp-auth"
    echo "NEXT_PRIVATE_SMTP_HOST=email-smtp.${SES_REGION}.amazonaws.com"
    echo "NEXT_PRIVATE_SMTP_PORT=587"
    echo "NEXT_PRIVATE_SMTP_USERNAME=$access_key_id"
    echo "NEXT_PRIVATE_SMTP_PASSWORD=$smtp_password"
    echo "NEXT_PRIVATE_SMTP_SECURE=false"
  } >"$OUTPUT_FILE"

  rm -f "$tmp_json"

  echo "Wrote SMTP credentials to $OUTPUT_FILE"
  echo "IAM user: $IAM_USER_NAME"
}

main "$@"
