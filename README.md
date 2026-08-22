# Dorarion Helm chart

This chart deploys Dorarion and its embedded background workers against an
externally operated PostgreSQL database. It runs `dorarion-core migrate` as a
blocking `pre-install,pre-upgrade` hook; the Deployment is not updated when a
migration fails.

## Prerequisites

- Kubernetes 1.28 or newer;
- Helm 3;
- an externally operated PostgreSQL database with tested backups;
- an immutable Dorarion image tag;
- an HTTPS public origin reachable by users and GitLab runners.

## Install

Create credentials before installation because the migration hook runs before
ordinary release resources. Generate the JWT secret and 256-bit encryption key
once and store their plaintext values in a password manager or secret manager:

```bash
kubectl create namespace dorarion

JWT_SECRET="$(openssl rand -hex 48)"
SECRET_ENCRYPTION_KEY="$(openssl rand -base64 32)"

kubectl -n dorarion create secret generic dorarion-secrets \
  --from-literal=DATABASE_URL='postgres://USER:PASSWORD@HOST:5432/DB_NAME' \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=SECRET_ENCRYPTION_KEY="$SECRET_ENCRYPTION_KEY"

unset JWT_SECRET SECRET_ENCRYPTION_KEY
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

The generated administrator password is displayed exactly once in the bootstrap
Job log. Helm cannot include the password in its installation output, so read
the Job log after the installation completes:

```bash
kubectl -n dorarion logs job/dorarion-bootstrap-admin
```

The output includes the generated username, email, and password. Save the
password immediately in a password manager, then delete the Job so the password
is no longer available to namespace readers:

```bash
kubectl -n dorarion delete job/dorarion-bootstrap-admin
```

If the release fullname differs, use the Job name printed by `helm install`.
Run `helm get notes dorarion --namespace dorarion` to display the retrieval
instructions again. The bootstrap command refuses to create an administrator
when a login account already exists.

Leave `bootstrapAdmin.enabled=false` for existing databases and all upgrades.

## Status

```bash
kubectl -n dorarion rollout status deployment/dorarion
kubectl -n dorarion get pods,jobs
kubectl -n dorarion port-forward service/dorarion 3000:80
curl --fail http://127.0.0.1:3000/health/ready
```

The API and the notification, webhook, deployment-reconciliation, and retention
workers run in the same container. Readiness proves the process can query
PostgreSQL; Dorarion does not yet expose separate worker-heartbeat probes.

## Upgrade

Back up PostgreSQL and the `SECRET_ENCRYPTION_KEY` before selecting a new
immutable image tag:

```bash
helm upgrade dorarion . \
  --namespace dorarion \
  --reuse-values \
  --set image.tag=0.0.2 \
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
helm lint . --set publicUrl=https://dorarion.example.com
helm template test . \
  --namespace dorarion \
  --set publicUrl=https://dorarion.example.com \
  --set image.tag=0.0.1

./tests/render.sh
```
