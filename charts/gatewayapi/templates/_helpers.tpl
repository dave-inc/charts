{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
Falls back to Release.Name when .Values.name is not provided.
*/}}
{{- define "gatewayapi.name" -}}
{{- default .Release.Name .Values.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "gatewayapi.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "gatewayapi.labels" -}}
helm.sh/chart: {{ include "gatewayapi.chart" . }}
{{ include "gatewayapi.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.additionalLabels }}
  {{- println "" }}
  {{- toYaml .Values.additionalLabels }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "gatewayapi.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gatewayapi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
