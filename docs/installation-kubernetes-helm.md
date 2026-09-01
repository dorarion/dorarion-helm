# Kubernetes + Helm + Dorarion

Simple cluster installation guide

> **Goal:** Install Dorarion from its public OCI Helm chart, connect it to an
> external PostgreSQL database, create the required Kubernetes Secret, create
> the first administrator, and verify the application.

- Run all commands from a terminal configured to access your Kubernetes cluster.
- This guide uses Helm chart `kimc1992/dorarion` version `0.0.3` from Docker Hub.
- Dorarion requires Kubernetes 1.28 or newer and Helm 3.
- PostgreSQL is not installed by this chart; prepare a database and backups first.
- A [PDF version](pdf/dorarion-kubernetes-helm-install-en.pdf) is also available.

## 1. Check Kubernetes and Helm

Confirm that `kubectl` points to the intended cluster before creating anything:

```bash
kubectl config current-context
kubectl cluster-info
kubectl version
helm version
```

Do not continue if the context names the wrong cluster. Dorarion requires a
Kubernetes server version of at least 1.28.

## 2. Check the published chart

Inspect the chart directly from Docker Hub:

```bash
helm show chart oci://registry-1.docker.io/kimc1992/dorarion \
  --version 0.0.3
```

The expected chart metadata is:

- Chart: `dorarion`
- Chart version: `0.0.3`
- Application version: `0.0.3`
- Application image: `kimc1992/dorarion-core:0.0.3`

## 3. Prepare PostgreSQL

Create an empty PostgreSQL database and a dedicated Dorarion user. The user
must be allowed to connect, create and alter tables, indexes, and constraints,
and run Dorarion's migrations.

Use your database provider's TLS requirements in the connection URL. A typical
URL has this form:

```text
postgres://USER:PASSWORD@HOST:5432/DB_NAME
```

Back up the database before every Dorarion upgrade. Test restoration separately;
the Helm chart does not operate or back up PostgreSQL.

### Optional: run a simple PostgreSQL pod

If you do not already have PostgreSQL, this repository provides a single-node
[PostgreSQL example](../examples/postgresql.yaml). It creates a 10 Gi persistent
volume claim, one PostgreSQL Deployment, and an internal ClusterIP Service.

> **This example is for learning and small test installations.** It is not
> highly available, does not configure TLS, and does not create backups. Use a
> managed database or a maintained PostgreSQL operator for production.

Create the namespace and a random PostgreSQL password:

```bash
kubectl create namespace dorarion --dry-run=client -o yaml | kubectl apply -f -

POSTGRES_PASSWORD="$(openssl rand -hex 32)"

kubectl -n dorarion create secret generic dorarion-postgresql \
  --from-literal=POSTGRES_DB=dorarion \
  --from-literal=POSTGRES_USER=dorarion \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
```

Deploy PostgreSQL directly from GitHub and wait until it is ready:

```bash
kubectl apply -f \
  https://raw.githubusercontent.com/dorarion/dorarion-helm/master/examples/postgresql.yaml

kubectl -n dorarion rollout status deployment/dorarion-postgresql \
  --timeout=5m
kubectl -n dorarion get pod,service,persistentvolumeclaim \
  -l app.kubernetes.io/name=dorarion-postgresql
```

If you opened a new terminal after creating PostgreSQL, recover the password
into a shell variable without displaying it:

```bash
POSTGRES_PASSWORD="$(kubectl -n dorarion get secret dorarion-postgresql \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode)"
```

For this example, set the database URL used in the next section:

```bash
DATABASE_URL="postgres://dorarion:${POSTGRES_PASSWORD}@dorarion-postgresql.dorarion.svc.cluster.local:5432/dorarion"
```

## 4. Create the namespace and Secret

The Secret must exist before `helm install` because database migration runs as
a pre-install hook.

Create the namespace:

```bash
kubectl create namespace dorarion --dry-run=client -o yaml | kubectl apply -f -
```

Generate the application secrets in your terminal and create the Kubernetes
Secret. If you used the PostgreSQL example, `DATABASE_URL` is already set.
For an external database, replace and run this first:

```bash
DATABASE_URL='postgres://USER:PASSWORD@HOST:5432/DB_NAME'
```

Then create the application Secret:

```bash
: "${DATABASE_URL:?Set DATABASE_URL before continuing}"
JWT_SECRET="$(openssl rand -hex 48)"
SECRET_ENCRYPTION_KEY="$(openssl rand -base64 32)"

kubectl -n dorarion create secret generic dorarion-secrets \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=SECRET_ENCRYPTION_KEY="$SECRET_ENCRYPTION_KEY"

unset DATABASE_URL POSTGRES_PASSWORD JWT_SECRET SECRET_ENCRYPTION_KEY
```

> **Protect these values.** Never commit them to Git, store them in Helm values,
> or post them in chat, screenshots, or tickets. Back up
> `SECRET_ENCRYPTION_KEY` in a password manager or secret manager. Losing it
> makes Dorarion's directly stored integration credentials unrecoverable.

Check only the Secret's key names, without printing their values:

```bash
kubectl -n dorarion describe secret dorarion-secrets
```

It must contain `DATABASE_URL`, `JWT_SECRET`, and `SECRET_ENCRYPTION_KEY`.

## 5. Install Dorarion and create the first administrator

Choose the real HTTPS address users and CI runners will use. Then install
Dorarion and enable administrator bootstrap for this first installation only:

```bash
helm upgrade --install dorarion \
  oci://registry-1.docker.io/kimc1992/dorarion \
  --version 0.0.3 \
  --namespace dorarion \
  --set publicUrl=https://dorarion.example.com \
  --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.username=admin \
  --set bootstrapAdmin.email=admin@example.com \
  --wait \
  --timeout 15m
```

Use an address reachable by users, GitLab runners, and other systems that send
reports or webhooks to Dorarion. Production installations should use HTTPS.

The installation performs these operations in order:

1. runs the blocking database migration Job;
2. creates the Dorarion Deployment and Service;
3. waits for the application to become ready;
4. runs the first-administrator bootstrap Job.

## 6. Save the administrator password

The bootstrap Job prints its generated password once. Read its logs:

```bash
kubectl -n dorarion logs job/dorarion-bootstrap-admin
```

Save the password immediately in a password manager. Then remove the Job so
namespace readers cannot retrieve the credential from its logs:

```bash
kubectl -n dorarion delete job dorarion-bootstrap-admin
```

Never enable `bootstrapAdmin` again for this database. Dorarion refuses to
bootstrap another administrator after a login account exists, but upgrades
should still explicitly leave it disabled.

## 7. Check the installation

Check the Helm release and Kubernetes workloads:

```bash
helm status dorarion --namespace dorarion
kubectl -n dorarion get deployment,pods,service,jobs
kubectl -n dorarion rollout status deployment/dorarion
```

If the migration fails, inspect its retained Job and logs:

```bash
kubectl -n dorarion get jobs
kubectl -n dorarion logs job/dorarion-migrate
```

The most common causes are an incorrect `DATABASE_URL`, blocked network access
to PostgreSQL, missing Secret keys, or insufficient database permissions.

## 8. Open Dorarion locally

For a quick check without an Ingress, forward the ClusterIP Service:

```bash
kubectl -n dorarion port-forward service/dorarion 3000:80
```

Keep that terminal open, then visit:

<http://127.0.0.1:3000/login>

Sign in with `admin` or `admin@example.com` and the password saved in Step 6.
In another terminal, verify readiness:

```bash
curl --fail http://127.0.0.1:3000/health/ready
```

## 9. Configure an Ingress

An Ingress controller and DNS must already exist. Create a local, non-secret
values file named `values.local.yaml`:

```yaml
publicUrl: https://dorarion.example.com

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: dorarion.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: dorarion-tls
      hosts:
        - dorarion.example.com
```

Apply it without enabling administrator bootstrap:

```bash
helm upgrade dorarion \
  oci://registry-1.docker.io/kimc1992/dorarion \
  --version 0.0.3 \
  --namespace dorarion \
  --reuse-values \
  --set bootstrapAdmin.enabled=false \
  --values values.local.yaml \
  --wait \
  --timeout 15m
```

Configure the TLS Secret according to your Ingress controller or certificate
manager. Do not add TLS private keys to a values file.

## 10. Upgrade Dorarion

Before an upgrade:

1. back up PostgreSQL and test that the backup can be restored;
2. back up the exact `SECRET_ENCRYPTION_KEY` and its key reference;
3. read the release notes and migration compatibility policy;
4. select a new immutable chart and application version.

Then upgrade, keeping administrator bootstrap disabled:

```bash
helm upgrade dorarion \
  oci://registry-1.docker.io/kimc1992/dorarion \
  --version NEW_CHART_VERSION \
  --namespace dorarion \
  --reuse-values \
  --set bootstrapAdmin.enabled=false \
  --wait \
  --timeout 15m
```

The pre-upgrade migration changes the database forward. Rolling back the Helm
release does not reverse a database migration.

## 11. Uninstall boundaries

Remove the Helm release with:

```bash
helm uninstall dorarion --namespace dorarion
```

This does not remove the external PostgreSQL database or the manually created
`dorarion-secrets` Secret. Preserve both when you may reinstall or restore.
Delete the namespace only when you deliberately want to remove all remaining
namespace resources.

If you deployed the sample PostgreSQL resources, they are also separate from
the Helm release. Removing its persistent volume claim deletes the database
when the storage class uses the usual `Delete` reclaim policy:

```bash
kubectl -n dorarion delete deployment,service dorarion-postgresql
kubectl -n dorarion delete persistentvolumeclaim dorarion-postgresql
kubectl -n dorarion delete secret dorarion-postgresql
```

Do not run the persistent volume claim deletion unless you intentionally want
to destroy the sample database and have any required backup.

## Quick recap

- Kubernetes context and version checked.
- Published OCI chart checked on Docker Hub.
- External PostgreSQL database and backups prepared.
- Or, for testing only, the single-node PostgreSQL example deployed.
- Namespace and required Kubernetes Secret created.
- Dorarion installed with first-install bootstrap enabled once.
- Generated administrator password saved and bootstrap Job removed.
- Deployment, readiness, and browser access verified.
- Future upgrades configured with bootstrap disabled.

## Official references

- [Dorarion Helm source](https://github.com/dorarion/dorarion-helm)
- [Dorarion chart on Docker Hub](https://hub.docker.com/repository/docker/kimc1992/dorarion/general)
- [Install Helm](https://helm.sh/docs/intro/install/)
- [Helm OCI registries](https://helm.sh/docs/topics/registries/)
- [Install kubectl](https://kubernetes.io/docs/tasks/tools/)
