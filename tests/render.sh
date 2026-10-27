#!/usr/bin/env bash
set -euo pipefail

readonly CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

helm lint "$CHART_DIR" \
  --set publicUrl=https://dorarion.example.com \
  --set image.digest= --set image.tag=reviewed-test-build \
  --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.email=admin@example.com

rendered="$(helm template test "$CHART_DIR" --set image.digest= --set image.tag=reviewed-test-build \
  --namespace dorarion \
  --set publicUrl=https://dorarion.example.com/ \
  --set image.digest= --set image.tag=reviewed-test-build \
  --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.email=admin@example.com \
  --set extraEnv[0].name=RUST_LOG \
  --set extraEnv[0].value=info)"

grep -Fq 'value: "2592000"' <<<"$rendered"
grep -Fq 'value: "https://dorarion.example.com"' <<<"$rendered"
grep -Fq 'name: SECRET_ENCRYPTION_KEY' <<<"$rendered"
grep -Fq 'name: RUST_LOG' <<<"$rendered"
grep -Fq 'app.kubernetes.io/component: bootstrap-admin' <<<"$rendered"
grep -Fq '"helm.sh/hook": pre-install,pre-upgrade' <<<"$rendered"

if helm template test "$CHART_DIR" --set image.digest= --set image.tag=reviewed-test-build \
  --set publicUrl=https://dorarion.example.com \
  --set bootstrapAdmin.enabled=true >/dev/null 2>&1; then
  echo 'expected bootstrapAdmin.email validation to fail' >&2
  exit 1
fi

if helm template test "$CHART_DIR" --set image.digest= --set image.tag=reviewed-test-build \
  --set publicUrl=https://dorarion.example.com \
  --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.email=invalid >/dev/null 2>&1; then
  echo 'expected invalid bootstrapAdmin.email validation to fail' >&2
  exit 1
fi

if helm template test "$CHART_DIR" --set image.digest= --set image.tag=reviewed-test-build >/dev/null 2>&1; then
  echo 'expected publicUrl validation to fail' >&2
  exit 1
fi


if helm template test "$CHART_DIR" --set image.digest= --set image.tag=reviewed-test-build --set publicUrl=http://example.com >/dev/null 2>&1; then
  echo 'expected HTTPS policy to fail' >&2; exit 1
fi
if helm template test "$CHART_DIR" --set image.digest= --set image.tag=reviewed-test-build --set publicUrl=https://example.com/dorarion >/dev/null 2>&1; then
  echo 'expected sub-path policy to fail' >&2; exit 1
fi
if helm template test "$CHART_DIR" --set image.digest= --set image.tag=reviewed-test-build --set publicUrl=https://example.com --set unknownTypo=true >/dev/null 2>&1; then
  echo 'expected unknown values to fail validation' >&2; exit 1
fi
# Allowlist entries accept hostnames/IPs/CIDRs, not URLs or hostname ports.
for setting in privateProviderHosts privateWebhookHosts; do
  for invalid in gitlab.corp.example:8443 https://gitlab.corp.example; do
    if helm template test "$CHART_DIR" --set publicUrl=https://example.com \
      --set-string "security.$setting[0]=$invalid" >/dev/null 2>&1; then
      echo "expected security.$setting to reject $invalid" >&2; exit 1
    fi
  done
done
policies="$(helm template test "$CHART_DIR" --set image.digest= --set image.tag=reviewed-test-build --set publicUrl=https://example.com --set replicaCount=2 --set networkPolicy.enabled=true --set podDisruptionBudget.enabled=true --set image.digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)"
grep -Fq 'kind: NetworkPolicy' <<<"$policies"
grep -Fq 'kind: PodDisruptionBudget' <<<"$policies"
grep -Fq 'name: DORARION_MIGRATE_ON_START' <<<"$policies"
grep -Fq 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' <<<"$policies"
# Check release image selection on every workload, including the optional listener.
release="$(helm template release-test "$CHART_DIR" \
  --set publicUrl=https://dorarion.example.com \
  --set bootstrapAdmin.enabled=true --set bootstrapAdmin.email=admin@example.com \
  --set listener.enabled=true --set listener.watcher.enabled=true \
  --set listener.watcher.receiverUrl=https://receiver.example.com)"
printf '%s\n' "$release" | python3 -c '
import sys,yaml
workloads=[d for d in yaml.safe_load_all(sys.stdin) if d and d["kind"] in ("Deployment","Job")]
assert len(workloads)==5, len(workloads)
for d in workloads:
    for c in d["spec"]["template"]["spec"]["containers"]:
        listener="listener" in d["metadata"]["name"]
        if not listener:
            assert d["metadata"]["labels"]["app.kubernetes.io/version"]=="0.0.8"
        expected=("docker.io/kimc1992/dorarion-listener@sha256:7427a98bce965ca4ebfa9a95c4f7bc99bbcdbadf88484a1b027378c497deeaf6" if listener else "docker.io/kimc1992/dorarion-core@sha256:156e422514c7974010483a8938c579453d02f884353b9b4b9b9919537fed9f97")
        assert c["image"]==expected, c["image"]
'
if ! command -v kubeconform >/dev/null; then echo 'kubeconform is required' >&2; exit 1; fi
printf '%s\n' "$rendered" | kubeconform -strict -kubernetes-version 1.34.0 -summary
printf '%s\n' "$policies" | kubeconform -strict -kubernetes-version 1.34.0 -summary
printf '%s\n' "$release" | kubeconform -strict -kubernetes-version 1.34.0 -summary

if helm template test "$CHART_DIR" --set publicUrl=https://example.com --set image.digest= --set image.tag= >/dev/null 2>&1; then
  echo 'expected explicit image selection to be required' >&2; exit 1
fi
if helm template test "$CHART_DIR" --set publicUrl=https://example.com --set image.digest= --set image.tag=reviewed-test-build --set database.statementTimeoutMs=999 >/dev/null 2>&1; then
  echo 'expected invalid statement timeout to fail' >&2; exit 1
fi
helm template test "$CHART_DIR" --set image.digest= --set image.tag=reviewed-test-build \
  --set publicUrl=https://example.com --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.email=admin@example.com \
  --set database.trustedHosts[0]=db.internal --set database.statementTimeoutMs=45000 \
  --set security.privateProviderHosts[0]=gitlab.internal \
  --set security.privateWebhookHosts[0]=hooks.internal \
  --set security.secretEnvAllowlist[0]=LEGACY_EXTERNAL \
  --set security.trustedProxies[0]=10.0.0.0/24 \
  --set security.reportRecipientDomains[0]=example.com \
  --set security.readmeImageOrigins[0]=https://gitlab.example.com \
  --set security.metricsScrapeTokenSecretKey=METRICS_TOKEN \
  --set extraEnvFrom[0].secretRef.name=external-credentials | python3 "$CHART_DIR/tests/verify-render.py"
python3 "$CHART_DIR/tests/registry.py"
echo 'Dorarion Helm render and shared-policy tests passed.'
