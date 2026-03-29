# Azure VM deployment for `sign.tomoai.io`

This bundle keeps Documenso on a single Azure VM with local Postgres, SES SMTP, and Caddy TLS termination.

## Files

- `docker/azure/compose.override.yml`: Adds a local build and Caddy to the upstream production Compose stack.
- `docker/azure/Caddyfile`: Reverse proxy for `sign.tomoai.io`.
- `scripts/aws/create-ses-smtp-credentials.sh`: Creates a dedicated IAM SMTP credential for SES and writes it to a local `.env`-style file.
- `scripts/aws/upsert-route53-a-record.sh`: Points `sign.tomoai.io` at the Azure VM public IP.
- `scripts/azure/render-sign-documenso-env.sh`: Renders `/opt/documenso/.env` contents without committing secrets.
- `scripts/azure/create-sign-documenso-vm.sh`: Provisions the resource group, network, public IP, NSG, NIC, and VM.
- `scripts/azure/bootstrap-sign-documenso-vm.sh`: Installs Docker and base packages on the VM.
- `scripts/azure/deploy-sign-documenso.sh`: Syncs this repo to the VM, installs the env file, generates the signing certificate, sets up cron backups, and runs `docker compose up -d --build`.
- `scripts/azure/backup-postgres.sh`: Nightly `pg_dump` job with 7-day retention.

## Expected env file

Render the env file with:

```bash
NEXT_PRIVATE_SMTP_USERNAME=... \
NEXT_PRIVATE_SMTP_PASSWORD=... \
NEXT_PRIVATE_GOOGLE_CLIENT_ID=... \
NEXT_PRIVATE_GOOGLE_CLIENT_SECRET=... \
NEXT_PRIVATE_AUTH_GOOGLE_ONLY=true \
NEXT_PRIVATE_AUTH_ALLOWED_EMAILS=eric@usetomo.com \
NEXT_PRIVATE_AUTH_ALLOWED_EMAIL_DOMAINS=usetomo.com \
scripts/azure/render-sign-documenso-env.sh
```

The output is written to `./.secrets/sign-documenso.env` by default and is meant to be copied to `/opt/documenso/.env` by the deploy script.

For Azure, the renderer also pins `DOCUMENSO_PORT_BIND=127.0.0.1` so the Remix app is not exposed directly on the VM public interface.

## Happy path

1. Create SES SMTP credentials.
2. Render the Documenso env file.
3. Create the Azure VM.
4. Bootstrap Docker on the VM.
5. Point `sign.tomoai.io` at the VM IP in Route53.
6. Deploy the repo to the VM.

The deploy script keeps the repo checkout on the VM so the same workflow can rebuild and redeploy any bug fix discovered during smoke testing.
