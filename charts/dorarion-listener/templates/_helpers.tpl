{{- define "listener.name" -}}{{ printf "%s-listener" .Release.Name | trunc 63 | trimSuffix "-" }}{{- end }}
{{- define "listener.image" -}}
{{- $registry := default .Values.image.registry .Values.global.imageRegistry -}}
{{- $image := printf "%s/%s" $registry .Values.image.repository -}}
{{- if .Values.image.digest -}}{{ $image }}@{{ .Values.image.digest }}{{- else -}}{{ $image }}:{{ .Values.image.tag }}{{- end -}}
{{- end }}
