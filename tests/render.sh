#!/usr/bin/env bash
set -euo pipefail

readonly CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

helm lint "$CHART_DIR" \
  --set publicUrl=https://dorarion.example.com \
  --set image.tag=0.0.1 \
  --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.email=admin@example.com

rendered="$(helm template test "$CHART_DIR" \
  --namespace dorarion \
  --set publicUrl=https://dorarion.example.com/ \
  --set image.tag=0.0.1 \
  --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.email=admin@example.com \
  --set extraEnv[0].name=SMTP_HOST \
  --set extraEnv[0].value=smtp.example.com)"

grep -Fq 'value: "2592000"' <<<"$rendered"
grep -Fq 'value: "https://dorarion.example.com"' <<<"$rendered"
grep -Fq 'name: SECRET_ENCRYPTION_KEY' <<<"$rendered"
grep -Fq 'name: SMTP_HOST' <<<"$rendered"
grep -Fq 'app.kubernetes.io/component: bootstrap-admin' <<<"$rendered"
grep -Fq '"helm.sh/hook": pre-install,pre-upgrade' <<<"$rendered"

if helm template test "$CHART_DIR" \
  --set publicUrl=https://dorarion.example.com \
  --set bootstrapAdmin.enabled=true >/dev/null 2>&1; then
  echo 'expected bootstrapAdmin.email validation to fail' >&2
  exit 1
fi

if helm template test "$CHART_DIR" \
  --set publicUrl=https://dorarion.example.com \
  --set bootstrapAdmin.enabled=true \
  --set bootstrapAdmin.email=invalid >/dev/null 2>&1; then
  echo 'expected invalid bootstrapAdmin.email validation to fail' >&2
  exit 1
fi

if helm template test "$CHART_DIR" >/dev/null 2>&1; then
  echo 'expected publicUrl validation to fail' >&2
  exit 1
fi

echo 'Dorarion Helm render tests passed.'
