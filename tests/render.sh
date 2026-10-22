#!/usr/bin/env bash
set -euo pipefail

readonly CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

helm lint "$CHART_DIR" \
  --set publicUrl=https://dorarion.example.com \
  --set image.tag=reviewed-test-build \
  --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.email=admin@example.com

rendered="$(helm template test "$CHART_DIR" --set image.tag=reviewed-test-build \
  --namespace dorarion \
  --set publicUrl=https://dorarion.example.com/ \
  --set image.tag=reviewed-test-build \
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

if helm template test "$CHART_DIR" --set image.tag=reviewed-test-build \
  --set publicUrl=https://dorarion.example.com \
  --set bootstrapAdmin.enabled=true >/dev/null 2>&1; then
  echo 'expected bootstrapAdmin.email validation to fail' >&2
  exit 1
fi

if helm template test "$CHART_DIR" --set image.tag=reviewed-test-build \
  --set publicUrl=https://dorarion.example.com \
  --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.email=invalid >/dev/null 2>&1; then
  echo 'expected invalid bootstrapAdmin.email validation to fail' >&2
  exit 1
fi

if helm template test "$CHART_DIR" --set image.tag=reviewed-test-build >/dev/null 2>&1; then
  echo 'expected publicUrl validation to fail' >&2
  exit 1
fi


if helm template test "$CHART_DIR" --set image.tag=reviewed-test-build --set publicUrl=http://example.com >/dev/null 2>&1; then
  echo 'expected HTTPS policy to fail' >&2; exit 1
fi
if helm template test "$CHART_DIR" --set image.tag=reviewed-test-build --set publicUrl=https://example.com/dorarion >/dev/null 2>&1; then
  echo 'expected sub-path policy to fail' >&2; exit 1
fi
if helm template test "$CHART_DIR" --set image.tag=reviewed-test-build --set publicUrl=https://example.com --set unknownTypo=true >/dev/null 2>&1; then
  echo 'expected unknown values to fail validation' >&2; exit 1
fi
policies="$(helm template test "$CHART_DIR" --set image.tag=reviewed-test-build --set publicUrl=https://example.com --set replicaCount=2 --set networkPolicy.enabled=true --set podDisruptionBudget.enabled=true --set image.digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)"
grep -Fq 'kind: NetworkPolicy' <<<"$policies"
grep -Fq 'kind: PodDisruptionBudget' <<<"$policies"
grep -Fq 'name: DORARION_MIGRATE_ON_START' <<<"$policies"
grep -Fq 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' <<<"$policies"
if ! command -v kubeconform >/dev/null; then echo 'kubeconform is required' >&2; exit 1; fi
printf '%s\n' "$rendered" | kubeconform -strict -kubernetes-version 1.34.0 -summary
printf '%s\n' "$policies" | kubeconform -strict -kubernetes-version 1.34.0 -summary

if helm template test "$CHART_DIR" --set publicUrl=https://example.com --set image.tag= >/dev/null 2>&1; then
  echo 'expected explicit image selection to be required' >&2; exit 1
fi
if helm template test "$CHART_DIR" --set publicUrl=https://example.com --set image.tag=reviewed-test-build --set database.statementTimeoutMs=999 >/dev/null 2>&1; then
  echo 'expected invalid statement timeout to fail' >&2; exit 1
fi
helm template test "$CHART_DIR" --set image.tag=reviewed-test-build \
  --set publicUrl=https://example.com --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.email=admin@example.com \
  --set database.trustedHosts[0]=db.internal --set database.statementTimeoutMs=45000 \
  --set security.secretEnvAllowlist[0]=LEGACY_EXTERNAL \
  --set security.trustedProxies[0]=10.0.0.0/24 \
  --set security.reportRecipientDomains[0]=example.com \
  --set security.readmeImageOrigins[0]=https://gitlab.example.com \
  --set security.metricsScrapeTokenSecretKey=METRICS_TOKEN \
  --set extraEnvFrom[0].secretRef.name=external-credentials | python3 "$CHART_DIR/tests/verify-render.py"
echo 'Dorarion Helm render and shared-policy tests passed.'
