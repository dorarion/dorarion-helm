# Dorarion Helm chart

This chart deploys Dorarion and its embedded background workers against an
externally operated PostgreSQL 16+ database. It runs `dorarion-core migrate` as a
blocking `pre-install,pre-upgrade` hook; the Deployment is not updated when a
migration fails.

## Images selected for testing

Chart `0.1.2` defaults to Docker Hub core `kimc1992/dorarion-core:0.0.6`.
The core tag must be published before installation or upgrade. `image.digest` is
empty; set it to the verified registry digest to pin an exact core artifact.
The optional listener remains `kimc1992/dorarion-listener:0.0.1`, pinned to its
existing linux/amd64 manifest digest. Use an amd64 node when enabling that image.
Previously packaged `.tgz` archives are unchanged.

Render the release images, including receiver and watcher, before installing:

```bash
helm template release-test . \
  --set publicUrl=https://dorarion.example.com \
  --set listener.enabled=true \
  --set listener.watcher.enabled=true \
  --set listener.watcher.receiverUrl=https://receiver.example.com
```

For a live listener installation, provision the restricted listener database role
and `dorarion-listener-secrets` first, and configure the receiver URL and watcher
credentials for your environment. See the listener repository README. Helm rendering
does not check database connectivity or image runtime compatibility.

A digest takes precedence over a tag. When testing another tag, clear the pin with
`--set image.digest= --set-string image.tag=NEW_TAG`; for listener use
`--set listener.image.digest= --set-string listener.image.tag=NEW_TAG`.

## Installation guides

Complete Kubernetes, PostgreSQL, and first-install walkthroughs are available
in Markdown and PDF:

| Language | Markdown | PDF |
| --- | --- | --- |
| English | [Read online](docs/installation-kubernetes-helm.md) | [Download PDF](docs/pdf/dorarion-kubernetes-helm-install-en.pdf) |
| 한국어 | [온라인 문서](docs/installation-kubernetes-helm-ko.md) | [PDF 다운로드](docs/pdf/dorarion-kubernetes-helm-install-ko.pdf) |
| 简体中文 | [在线文档](docs/installation-kubernetes-helm-zh-cn.md) | [下载 PDF](docs/pdf/dorarion-kubernetes-helm-install-zh-cn.pdf) |

## Prerequisites

- Kubernetes 1.28 or newer;
- Helm 3;
- an externally operated PostgreSQL database with tested backups;
- a Dorarion image tag or digest built from the reviewed core source;
- an HTTPS public origin reachable by users and GitLab runners.

## Install

The defaults select the core `0.0.6` tag. To use another release,
override `image.repository` and `image.digest` with that release's coordinates.

Create credentials before installation because the migration hook runs before
ordinary release resources. Generate the JWT secret and 256-bit encryption key
once and store their plaintext values in a password manager or secret manager:

```bash
kubectl create namespace dorarion

JWT_SECRET="$(openssl rand -hex 48)"
SECRET_ENCRYPTION_KEY="$(openssl rand -base64 32)"
DORARION_BOOTSTRAP_PASSWORD="$(openssl rand -hex 24)"

kubectl -n dorarion create secret generic dorarion-secrets \
  --from-literal=DATABASE_URL='postgres://USER:PASSWORD@HOST:5432/DB_NAME?sslmode=verify-full' \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=SECRET_ENCRYPTION_KEY="$SECRET_ENCRYPTION_KEY" \
  --from-literal=DORARION_BOOTSTRAP_PASSWORD="$DORARION_BOOTSTRAP_PASSWORD"

unset JWT_SECRET SECRET_ENCRYPTION_KEY DORARION_BOOTSTRAP_PASSWORD
```

Install and optionally create the first administrator. Bootstrap must only be
enabled for a new database with no Dorarion accounts:

```bash
helm upgrade --install dorarion . \
  --namespace dorarion \
  --set publicUrl=https://dorarion.example.com \
  --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.email=you@example.com \
  --wait \
  --timeout 15m
```

Bootstrap reads a pre-created Secret key `DORARION_BOOTSTRAP_PASSWORD` (at least
16 characters). Put it in the same Secret as the database and encryption keys.
Retrieve it from your secret manager; bootstrap logs do not contain it. The
bootstrap hook does not migrate or reset an existing administrator.

## Status

```bash
kubectl -n dorarion rollout status deployment/dorarion
kubectl -n dorarion get pods,jobs
kubectl -n dorarion port-forward service/dorarion 3000:80
curl --fail http://127.0.0.1:3000/health/ready
```

The API and the notification, webhook, deployment-reconciliation, and retention
workers run in the same container. Readiness proves the process can query
PostgreSQL. Worker health is reported separately. Liveness remains process-only; authenticated `/health/workers` contains worker status.

## Upgrade

Back up PostgreSQL and the `SECRET_ENCRYPTION_KEY` before selecting a new
immutable image tag:

```bash
read -r -p "New image digest (sha256:...): " DORARION_IMAGE_DIGEST
helm upgrade dorarion . \
  --namespace dorarion \
  --reuse-values \
  --set-string image.digest="$DORARION_IMAGE_DIGEST" \
  --set bootstrapAdmin.enabled=false \
  --wait \
  --timeout 15m
```

The pre-upgrade migration is a forward database operation. Rolling back the
Helm release does not reverse it. Follow Dorarion's supported-version and
migration compatibility policy before rollback.

## Secrets and optional environment

The chart never stores secret values in Helm values. `existingSecret` must
contain the keys selected by `secretKeys.databaseUrl`, `secretKeys.jwtSecret`,
and `secretKeys.encryptionKey` before installation. The blocking migration hook
references all three, so a missing key prevents the release from rolling out.
Losing the encryption key makes directly stored GitLab, Argo CD, and webhook
credentials unrecoverable.

Use `extraEnv` with `valueFrom.secretKeyRef` for SMTP passwords, notification
webhooks, or other secret-backed environment variables. Use `rollout.restartAt`
to trigger a controlled rollout after changing an externally managed Secret:

```bash
helm upgrade dorarion . \
  --namespace dorarion \
  --reuse-values \
  --set-string rollout.restartAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --wait
```

Private/loopback webhook destinations remain blocked by default. Enable
`security.allowPrivateWebhookDestinations` only for reviewed internal targets.

## Backup and restore boundary

This chart does not install PostgreSQL and cannot safely infer how an external
database is replicated, encrypted, backed up, or restored. Use the database
operator or managed service's native physical/snapshot backup mechanism, and
test restoration into an isolated database. A complete Dorarion backup contains:

1. the PostgreSQL database;
2. the exact `SECRET_ENCRYPTION_KEY` and its key reference;
3. the Helm values and immutable application image tag;
4. externally referenced SMTP and notification credentials.

Scale Dorarion to zero before an in-place restore, restore PostgreSQL using the
database operator, run the migration hook through `helm upgrade`, and wait for
readiness before restoring traffic.

## Validate changes

`publicUrl` is intentionally required:

```bash
helm lint . --set publicUrl=https://dorarion.example.com --set image.tag=validation-only
helm template test . \
  --namespace dorarion \
  --set publicUrl=https://dorarion.example.com \
  --set image.tag=validation-only

./tests/render.sh
```

## October feedback changes

Use a dedicated HTTPS hostname; mounting Dorarion under `/dorarion` is unsupported.
`allowInsecurePublicUrl=true` is an explicit local-development exception.
Set `image.digest=sha256:…` from the verified organization GHCR release; a digest
wins over `image.tag`. No release image is published by this chart change.

The pre-install/pre-upgrade Job alone runs migrations; application startup
migration is disabled. Existing databases must be backed up before an upgrade.
Bootstrap reads `secretKeys.bootstrapPassword` from `existingSecret` and does not
print the password. Supply at least 16 characters and retrieve it from your
Secret manager. Existing administrator accounts are not overwritten.

`extraVolumes` and `extraVolumeMounts` apply to the server and both Jobs. Mount a
corporate CA bundle read-only and set `SSL_CERT_FILE` through `extraEnv`.
PostgreSQL URLs outside loopback require `sslmode=verify-full`; configure the
PostgreSQL root certificate in the URL. The explicit insecure development option
is `DORARION_ALLOW_INSECURE_DATABASE=true` in `extraEnv`.

Enable `networkPolicy` with explicit ingress and egress rules, including DNS,
PostgreSQL, GitLab/Argo, LDAP, SMTP and configured webhook endpoints. Empty rules
deny all selected traffic, including hook Jobs. Enable `podDisruptionBudget`
when replicaCount and available resources can satisfy minAvailable; replicas do
not establish an HA guarantee. Hook Job logs contain no bootstrap secret.

The PostgreSQL example is development-only: it has neither verified TLS nor
backup/HA guarantees. Download and inspect checked-out manifests before applying
them. Use your managed database and certificate configuration for persistent
installations. Create the namespace and existing Secret before Helm installation.

## Reviewed core configuration

The default pins target the Docker Hub test images listed above. For another
release, select its reviewed repository and SHA-256 digest. Previously packaged
`.tgz` archives are unchanged; install the checked-out chart.

The API pool defaults to 15, with a separate six-connection worker pool per
replica. Budget database connections for replicas and hook Jobs. Set
`database.statementTimeoutMs` (1000–300000), and trust internal database hosts
only with `database.trustedHosts`; external databases require verify-full TLS.

`security.secretEnvAllowlist`, `trustedProxies`, `reportRecipientDomains` and
`readmeImageOrigins` expose the corresponding startup policies. Put external
credentials under DORARION_EXT_ variables in Secret-backed extraEnv/extraEnvFrom.
Core secrets can never be allowlisted. All three workloads receive the same
policy and extraEnvFrom. Migration and bootstrap Jobs reference the required JWT,
issuer/audience and encryption configuration. Set
`security.metricsScrapeTokenSecretKey` to a key in existingSecret for a dedicated
32–512-character monitoring bearer credential; no token belongs in values.yaml.

Readiness checks PostgreSQL; /health/workers reports worker status separately.
Startup migration is disabled because the blocking hook owns migration.
terminationGracePeriodSeconds defaults to 120 so the process can drain workers.
Back up the exact encryption key with PostgreSQL; follow the bundled migration
pre-checks and rotate Argo application tokens when upgrading to the audited core.

## Beta database baseline — 2026-10-10

The reviewed core source now installs two consolidated migrations. Earlier beta
databases require a new empty database or an explicit data-losing reinstall; this
is not an in-place migration from the previous 80-file chain. Do not delete only
the SQLx ledger or reuse an earlier image after initializing the new schema.
See the core migrations/README.md for the reinstall procedure. Existing data is
not automatically deleted by Compose scripts or Helm hooks. Build a fresh image
from the reviewed source and use a new immutable tag/digest. Listener is optional.
