{{/*
Cloud Armor chart name (BackendConfig / FrontendConfig / Certificate).
Defaults to .Release.Name if .Values.name is not set.
*/}}
{{- define "cloudarmor.name" -}}
{{- default .Release.Name .Values.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
TLS secret name for certificate.
*/}}
{{- define "cloudarmor.tlsSecret" -}}
{{- if .Values.certificate.secretName }}
{{- .Values.certificate.secretName }}
{{- else }}
{{- printf "%s-ca-tls" .Values.certificate.host | replace "." "-" }}
{{- end }}
{{- end }}

{{/*
Common Helm labels (applied to all resources).
*/}}
{{- define "cloudarmor.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "cloudarmor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}
