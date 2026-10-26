{{- define "dorarion.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "dorarion.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "dorarion.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "dorarion.labels" -}}
helm.sh/chart: {{ include "dorarion.chart" . }}
{{ include "dorarion.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{- define "dorarion.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dorarion.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "dorarion.image" -}}
{{- $repository := .Values.image.repository -}}
{{- $registry := default .Values.image.registry .Values.global.imageRegistry -}}
{{- if $registry -}}
{{- if regexMatch "^([^/]*[.:][^/]*|localhost)/" $repository -}}
{{- $repository = regexReplaceAll "^[^/]+/" $repository "" -}}
{{- end -}}
{{- $repository = printf "%s/%s" $registry $repository -}}
{{- end -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" $repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" $repository (required "Set image.tag or image.digest to an image built from the reviewed core source" .Values.image.tag) }}
{{- end }}
{{- end }}

{{- define "dorarion.secretName" -}}
{{- required "existingSecret is required and must exist before installing Dorarion" .Values.existingSecret }}
{{- end }}

{{- define "dorarion.publicUrl" -}}
{{- $url := required "publicUrl is required (for example https://dorarion.example.com)" .Values.publicUrl -}}
{{- if not (regexMatch "^https?://" $url) -}}
{{- fail "publicUrl must be an absolute HTTP or HTTPS URL" -}}
{{- end -}}
{{- if and (not .Values.allowInsecurePublicUrl) (not (hasPrefix "https://" $url)) -}}
{{- fail "publicUrl requires HTTPS; use allowInsecurePublicUrl only for local development" -}}
{{- end -}}
{{- if not (regexMatch "^https?://[^/?#]+/?$" $url) -}}
{{- fail "publicUrl must use a dedicated hostname without a sub-path" -}}
{{- end -}}
{{- $url | trimSuffix "/" -}}
{{- end }}

{{- define "dorarion.bootstrapEmail" -}}
{{- $email := required "bootstrapAdmin.email is required when bootstrap is enabled" .Values.bootstrapAdmin.email -}}
{{- if not (regexMatch "^[^@[:space:]]+@[^@[:space:]]+$" $email) -}}
{{- fail "bootstrapAdmin.email must be a valid email address" -}}
{{- end -}}
{{- $email -}}
{{- end }}

{{/* Startup-validated policy used identically by server and CLI Jobs. */}}
{{- define "dorarion.installationPolicyEnv" -}}
{{- with .Values.security.privateProviderHosts }}
- name: DORARION_ALLOWED_PRIVATE_PROVIDER_HOSTS
  value: {{ join "," . | quote }}
{{- end }}
{{- with .Values.security.privateWebhookHosts }}
- name: DORARION_ALLOWED_PRIVATE_WEBHOOK_HOSTS
  value: {{ join "," . | quote }}
{{- end }}
{{- if .Values.security.metricsScrapeTokenSecretKey }}
- name: DORARION_METRICS_SCRAPE_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "dorarion.secretName" . }}
      key: {{ .Values.security.metricsScrapeTokenSecretKey }}
{{- end }}
- name: DORARION_DATABASE_TRUSTED_HOSTS
  value: {{ join "," .Values.database.trustedHosts | quote }}
- name: DORARION_DB_STATEMENT_TIMEOUT_MS
  value: {{ .Values.database.statementTimeoutMs | int64 | quote }}
- name: DORARION_SECRET_ENV_ALLOWLIST
  value: {{ join "," .Values.security.secretEnvAllowlist | quote }}
- name: DORARION_TRUSTED_PROXIES
  value: {{ join "," .Values.security.trustedProxies | quote }}
- name: DORARION_REPORT_RECIPIENT_DOMAINS
  value: {{ join "," .Values.security.reportRecipientDomains | quote }}
- name: DORARION_README_IMAGE_ORIGINS
  value: {{ join "," .Values.security.readmeImageOrigins | quote }}
{{- end }}
