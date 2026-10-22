# Historical manual publishing procedure

Application releases now use the core `.github/workflows/release.yml` verified
CI, organizational GHCR image digest, SBOM, scan and OIDC signature workflow.
The commands below are retained as a development reference, not a supported
production release path. Do not promote personally hosted or unsigned images.
Use a new immutable version and the verified digest for Helm promotion.

Publish in this order:

1. push the core source;
2. build and push an immutable application image;
3. update and push the Helm source;
4. package and push the chart to the OCI registry.

Never commit `.env`, `.env.live`, database credentials, JWT secrets, encryption
keys, registry tokens, or local values containing secrets.

## 1. Choose new versions

Run these commands from the `dorarion-helm` repository and replace the example
versions with the versions being released:

```bash
export DORARION_APP_VERSION=0.0.3
export DORARION_CHART_VERSION=0.0.3
```

Application image tags and chart versions are immutable. Do not overwrite an
already published version.

## 2. Push the core source

Check and test the core repository before pushing it:

```bash
git -C ../dorarion-core status --short --branch
cargo test --manifest-path ../dorarion-core/Cargo.toml --locked
git -C ../dorarion-core push origin main
```

Stop if the status contains unexpected or secret files.

## 3. Build and push the application image

The chart currently uses Docker Hub repository `kimc1992/dorarion-core`.
Authenticate, create a Buildx builder if needed, and publish AMD64 and ARM64:

```bash
docker login
docker buildx inspect --bootstrap
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag "kimc1992/dorarion-core:${DORARION_APP_VERSION}" \
  --push \
  ../dorarion-core
```

Verify that the immutable tag exists:

```bash
docker buildx imagetools inspect \
  "kimc1992/dorarion-core:${DORARION_APP_VERSION}"
```

## 4. Update and validate the Helm chart

In `Chart.yaml`, set:

```yaml
version: 0.0.3
appVersion: "0.0.3"
```

In `values.yaml`, set:

```yaml
image:
  repository: kimc1992/dorarion-core
  tag: "0.0.3"
```

Use the actual values from `DORARION_CHART_VERSION` and
`DORARION_APP_VERSION`. Then validate and review the release:

```bash
./tests/render.sh
git diff --check
git diff
git status --short --branch
```

Commit and push the Helm source:

```bash
git add .gitignore .helmignore Chart.yaml values.yaml dev/HOW_TO_PUSH.md
git commit -m "release dorarion chart ${DORARION_CHART_VERSION}"
git push origin master
```

## 5. Package and publish the Helm chart

Publish the chart as an OCI artifact to Docker Hub using the same `kimc1992`
account as the application image. The chart repository is
[`kimc1992/dorarion`](https://hub.docker.com/repository/docker/kimc1992/dorarion/general):

```bash
helm registry login registry-1.docker.io --username kimc1992
helm package .
helm push "dorarion-${DORARION_CHART_VERSION}.tgz" \
  oci://registry-1.docker.io/kimc1992
```

Helm takes the repository basename from `name: dorarion` in `Chart.yaml`, so
the resulting artifact is:

```text
registry-1.docker.io/kimc1992/dorarion:${DORARION_CHART_VERSION}
```

The generated `.tgz` is ignored by Git.

Verify the published chart without installing it:

```bash
helm show chart oci://registry-1.docker.io/kimc1992/dorarion \
  --version "${DORARION_CHART_VERSION}"
```

## 6. Install or upgrade

Create the namespace and required Secret before the first installation. Do not
put the secret values in a committed values file.

```bash
helm upgrade --install dorarion \
  oci://registry-1.docker.io/kimc1992/dorarion \
  --version "${DORARION_CHART_VERSION}" \
  --namespace dorarion \
  --create-namespace \
  --set publicUrl=https://dorarion.example.com \
  --wait \
  --timeout 15m
```

For a new, empty database only, add:

```bash
--set bootstrapAdmin.enabled=true \
--set bootstrapAdmin.email=you@example.com
```

For upgrades, leave `bootstrapAdmin.enabled=false` and back up PostgreSQL and
`SECRET_ENCRYPTION_KEY` first.
