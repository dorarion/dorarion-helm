# Publishing core images and Helm charts

Core images use Docker Hub `kimc1992/dorarion-core`; charts use Docker Hub OCI
`registry-1.docker.io/kimc1992/dorarion`. Keep release tags immutable.

## Build the core image

Follow the core [multi-platform release procedure](../../dorarion-core/docs/multi-platform-releases.md).
It includes the correct Buildx builder, automatic version selection, amd64/arm64
builds, and index verification. The core GitHub release workflow builds and tests
both architectures before publishing the single release tag.

Use the shared image-index digest for installation defaults. The per-architecture
digest entries are for inspection, not for a multi-platform default pin.

## Update the chart

After the new core image is published and verified, update `image.tag` and
`image.digest` together, set Chart.yaml appVersion, and increase the chart version.
Update the release expectations in `tests/render.sh` and the installation docs.
The optional listener keeps its own independent image/platform support.

```bash
bash tests/render.sh
git diff --check
git diff
```

Review and commit the core and distribution changes. Never commit private env
files, credentials, registry tokens, or local values. Keep published images unchanged; use a new version when adding platform support.

## Publish the reviewed Helm package

```bash
DORARION_CHART_VERSION="$(helm show chart . | sed -n 's/^version: //p')"
: "${DORARION_CHART_VERSION:?Chart version is required}"
helm registry login registry-1.docker.io --username kimc1992
helm package .
helm push "dorarion-${DORARION_CHART_VERSION}.tgz" \
  oci://registry-1.docker.io/kimc1992
helm show chart oci://registry-1.docker.io/kimc1992/dorarion \
  --version "$DORARION_CHART_VERSION"
```

For deployment, use the README's Secret, backup, migration, and bootstrap
instructions. Do not enable the amd64-only listener on an ARM64 node.
