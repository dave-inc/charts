{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
Falls back to Release.Name when .Values.name is not provided.
*/}}
{{- define "gateway-bundle.name" -}}
{{- default .Release.Name .Values.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "gateway-bundle.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "gateway-bundle.labels" -}}
helm.sh/chart: {{ include "gateway-bundle.chart" . }}
{{ include "gateway-bundle.selectorLabels" . }}
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
{{- define "gateway-bundle.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gateway-bundle.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
