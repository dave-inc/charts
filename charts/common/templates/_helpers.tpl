{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
*/}}
{{- define "common.name" -}}
{{- default .Release.Name ( required ".Values.name is missing, this can be caused by a mismatch in chart alias reference" .Values.name ) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Canary common name
*/}}
{{- define "common.canaryName" -}}
{{- printf "%s-canary" (include "common.name" .) }}
{{- end }}

{{/*
Control common name
*/}}
{{- define "common.controlName" -}}
{{- printf "%s-control" (include "common.name" .) }}
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
Selector labels builder
*/}}
{{- define "common.selectorLabelsBuilder" -}}
app.kubernetes.io/name: {{ include "common.name" (index . 0) }}{{ index . 2}}
app.kubernetes.io/instance: {{ index . 1}}{{ index . 2}}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "common.selectorLabels" -}}
{{ include "common.selectorLabelsBuilder" (list . .Release.Name "") }}
{{- end }}

{{/*
Reverse proxy selector labels (used if canary is enabled)
*/}}
{{- define "common.reverseProxySelectorLabels" -}}
{{ include "common.selectorLabelsBuilder" (list . .Release.Name "-rproxy") }}
{{- end }}

{{/*
Canary selector labels
*/}}
{{- define "common.canarySelectorLabels" -}}
{{ include "common.selectorLabelsBuilder" (list . .Release.Name "-canary") }}
{{- end }}

{{/*
Control selector labels
*/}}
{{- define "common.controlSelectorLabels" -}}
{{ include "common.selectorLabelsBuilder" (list . .Release.Name "-control") }}
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
{{- if .Values.cloudsqlProxy.instanceConnectionName -}}
  {{- .Values.cloudsqlProxy.instanceConnectionName -}}
{{- else if .Values.cloudsqlProxy.migrationTemplate.instanceConnectionName -}}
  {{- .Values.cloudsqlProxy.migrationTemplate.instanceConnectionName -}}
{{- else if .Values.cloudsqlProxy.enabled -}}
  {{- if .Values.cloudsqlProxy.command -}}
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
Reverse Proxy common name
*/}}
{{- define "common.reverseProxyName" -}}
{{- printf "%s-rproxy" (include "common.name" .) }}
{{- end }}

{{/*
Fail rather than let a Pod be SIGKILLed part-way through its preStop sleep.
Expects a dict of "sleep", "grace" and "tier".
*/}}
{{- define "common.validateDrainBudget" -}}
{{- if ge (.sleep | int) (.grace | int) -}}
{{- fail (printf "%s: preStop sleep of %vs must be shorter than terminationGracePeriodSeconds of %vs, otherwise the Pod is SIGKILLed before it finishes draining" .tier .sleep .grace) -}}
{{- end -}}
{{- end -}}

{{/*
Effective autoscaling.minReplicas.

Left unset in values.yaml so the chart can tell a deliberate value from an inherited
one. Canary puts a second Deployment in the traffic path, and a tier at one Pod has no
headroom while that Pod is replaced, so a canary-enabled service defaults to 2. Without
canary a service may legitimately run a single Pod, so the default stays 1. An explicit
autoscaling.minReplicas always wins, including 1.

Only the default is capped at maxReplicas, so the chart never invents an invalid HPA,
while an explicit min above max is still surfaced by the API server rather than masked.

Expects a dict of "ctx" and "max".
*/}}
{{- define "common.minReplicas" -}}
{{- /* Not default: it treats 0 as empty, which would ignore an explicit 0. */ -}}
{{- if not (kindIs "invalid" .ctx.Values.autoscaling.minReplicas) -}}
{{- .ctx.Values.autoscaling.minReplicas | int -}}
{{- else if .ctx.Values.canary.enabled -}}
{{- min 2 (.max | int) -}}
{{- else -}}
1
{{- end -}}
{{- end -}}

{{/*
Lifecycle for the application containers of the control and canary Deployments.

An explicit deploymentContainer.lifecycle wins. Otherwise a preStop sleep keeps the
Pod in the traffic path while the load balancer detaches its endpoint, which lags the
Pod being killed. terminationGracePeriodSeconds cannot do this on its own: it bounds
how long shutdown may take, it does not stop the container from exiting on SIGTERM.

Uses the native sleep action rather than an exec of /bin/sh. It needs no shell in the
image, so it also works on distroless and scratch bases, where an exec hook fails with
FailedPreStopHook and silently leaves the container with no drain at all. The reverse
proxy and the cloudsqlProxy sidecar still use exec because their hooks combine the
sleep with another command, which the sleep action cannot express. Requires the
kubeVersion floor in Chart.yaml.
*/}}
{{- define "common.appLifecycle" -}}
{{- if .Values.deploymentContainer.lifecycle }}
lifecycle:
  {{- toYaml .Values.deploymentContainer.lifecycle | nindent 2 }}
{{- else if gt (.Values.preStopSleepSeconds | default 0 | int) 0 }}
{{- include "common.validateDrainBudget" (dict "sleep" .Values.preStopSleepSeconds "grace" .Values.terminationGracePeriodSeconds "tier" "application container") }}
lifecycle:
  preStop:
    sleep:
      seconds: {{ .Values.preStopSleepSeconds | int }}
{{- end }}
{{- end }}
