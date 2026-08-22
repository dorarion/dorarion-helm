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
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}

{{- define "dorarion.secretName" -}}
{{- required "existingSecret is required and must exist before installing Dorarion" .Values.existingSecret }}
{{- end }}

{{- define "dorarion.publicUrl" -}}
{{- $url := required "publicUrl is required (for example https://dorarion.example.com)" .Values.publicUrl -}}
{{- if not (regexMatch "^https?://" $url) -}}
{{- fail "publicUrl must be an absolute HTTP or HTTPS URL" -}}
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
