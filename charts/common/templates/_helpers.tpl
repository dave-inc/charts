{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
*/}}
{{- define "common.name" -}}
{{- default .Release.Name ( required ".Values.name is missing, this can be caused by a mismatch in chart alias reference" .Values.name ) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "common.labels" -}}
helm.sh/chart: {{ include "common.chart" . }}
{{ include "common.selectorLabels" . }}
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
{{- define "common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "common.serviceAccountName" -}}
{{- if and (.Values.serviceAccount.create) (not .Values.serviceAccount.existingNameSA) }}
{{- default (include "common.name" .) .Values.serviceAccount.name }}
{{- else if and (not .Values.serviceAccount.create) (.Values.serviceAccount.existingNameSA) }}
{{- default (include "common.name" .) .Values.serviceAccount.existingNameSA }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create Cloud Armor name which will be used for Service and Ingress names.
This is needed to avoid overlap with default Service and Ingress (the ones not used by Cloud Armor)
*/}}
{{- define "common.cloudArmorName" -}}
{{- if and (.Values.cloudArmor.enabled) (.Values.cloudArmor.name) }}
{{- .Values.cloudArmor.name }}
{{- else }}
{{- printf "%s-%s" (include "common.name" .) "ca" }}
{{- end }}
{{- end }}


{{/*
Create Cloud Armor tls secret name.
This is needed to avoid overlap with default Service and Ingress (the ones not used by Cloud Armor)
*/}}
{{- define "common.cloudArmorTlsSecret" -}}
{{- if .Values.cloudArmor.enabled }}
{{- printf "%s-ca-tls" .Values.cloudArmor.certificate.host | replace "." "-" }}
{{- end }}
{{- end }}

{{/*
Name for the custom config configmap.
*/}}
{{- define "common.customConfig.name" -}}
{{ .Values.customConfig.name | default (print (include "common.name" .) "-customconfig") }}
{{- end -}}


{{/*
Create common.cloudsqlProxyVersion depending on .Values.cloudsqlProxy.image.repository depending on the image used.
Either gcr.io/cloudsql-docker/gce-proxy:1.* or with gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.*
*/}}
{{- define "common.cloudsqlProxyVersion" -}}
{{- if hasPrefix "gcr.io/cloudsql-docker/gce-proxy:1" .Values.cloudsqlProxy.image.repository }}
{{- printf "v1" }}
{{- else if hasPrefix "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2" .Values.cloudsqlProxy.image.repository }}
{{- printf "v2" }}
{{- else }}
{{- fail "cloudsqlProxyVersion is not supported" }}
{{- end }}
{{- end }}

{{/*
Create common.instanceConnectionName depending on .Values.cloudsqlProxy.instanceConnectionName
else if .Values.cloudsqlProxy.migrationTemplate.instanceConnectionName
else if try to extract it from the .Values.cloudsqlProxy.command list
else if try to extract it from the .Values.cloudsqlProxy.args list
else fail.
This variable will be used in deployment.yaml and workflowtemplate.yaml it's a safer way to get the instanceConnectionName.
Once all apps are using cloud sql proxy v2 this can be simplified.
*/}}
{{- define "common.instanceConnectionName" -}}
{{- if .Values.cloudsqlProxy.enabled -}}
  {{- if .Values.cloudsqlProxy.instanceConnectionName -}}
    {{- .Values.cloudsqlProxy.instanceConnectionName  -}}
  {{- else if .Values.cloudsqlProxy.migrationTemplate.instanceConnectionName -}}
    {{- .Values.cloudsqlProxy.migrationTemplate.instanceConnectionName  -}}
  {{- else if .Values.cloudsqlProxy.command -}}
    {{- $commandList := .Values.cloudsqlProxy.command -}}
    {{- $instanceArg := "" -}}
    {{- range $cmd := $commandList -}}
      {{- if hasPrefix "-instances=" $cmd -}}
        {{- $instanceArg = $cmd -}}
      {{- end -}}
    {{- end -}}
    {{- trimPrefix "-instances=" $instanceArg }}
  {{- else if .Values.cloudsqlProxy.args -}}
    {{- $argsList := .Values.cloudsqlProxy.args -}}
    {{- $instanceArg := "" -}}
    {{- range $arg := $argsList -}}
      {{- if not (hasPrefix "-" $arg) -}}
        {{- $instanceArg = $arg -}}
        {{- break -}}
      {{- end -}}
    {{- end -}}
    {{- $instanceArg | regexFind "^[^?]+" | trim -}}
  {{- else -}}
    {{- fail "Can't get instanceConnectionName in .Values.cloudsqlProxy.instanceConnectionName|command|args or properties not set" -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Creates ingressStyles based on the canary deployment and migration settings.
*/}}
{{- define "ingressStyles" -}}
  {{- $ingressStyle := list "legacy" }}
  {{- if and .Values.canary.enabled (.Values.canary.migration) }}
    {{- $ingressStyle = append $ingressStyle "csm" }}
  {{- else if and .Values.canary.enabled (not .Values.canary.migration) }}
    {{- $ingressStyle = list "csm" }}
  {{- end }}
  {{- toJson $ingressStyle }}
{{- end -}}
