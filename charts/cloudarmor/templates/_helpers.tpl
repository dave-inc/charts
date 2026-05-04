{{/*
Cloud Armor chart name (BackendConfig / FrontendConfig).
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
Default backend port for ingress when not specified per path.
*/}}
{{- define "cloudarmor.defaultBackendPort" -}}
80
{{- end }}
