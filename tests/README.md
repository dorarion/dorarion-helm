# Helm tests

`dorarion-helm` owns the chart, its listener subchart, and all chart-specific tests.
Core does not carry a second chart copy.

Run the standard suite with Helm, Python/PyYAML, and kubeconform installed:

```bash
bash tests/render.sh
```

It covers schema validation, rendered workloads, shared startup policy, image
selection, registry overrides, pull secrets, and the standalone listener chart.
The Helm repository's CI runs this command.

The opt-in development Kubernetes rehearsal is:

```bash
python3 tests/acceptance/helm_install_upgrade.py
```

It requires the existing local k3d/PostgreSQL development setup, an Argo Application
CRD, a restricted listener DB role, and local images. Development connection files
default to the sibling `dorarion-core` checkout; override `DORARION_CORE_DIR` when
it is elsewhere. Select the intended `KUBECONFIG` explicitly.

Build/import images tagged `docker.io/library/dorarion-core:helm-test` and
`docker.io/library/dorarion-listener:helm-test`, or set `DORARION_HELM_CORE_IMAGE`
and `DORARION_HELM_LISTENER_IMAGE`. The rehearsal clears distribution digest pins
so it tests those selected local images. It creates and removes its own namespace
and database. This specialized rehearsal currently imports amd64 images and is
not an ARM64 release test.
