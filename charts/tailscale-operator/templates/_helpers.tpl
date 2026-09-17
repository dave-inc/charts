{{/*
Expand the name of the chart.
*/}}
{{- define "tailscale-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "tailscale-operator.fullname" -}}
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

{{/*
Name of the CRS-only kube-state-metrics workload. Unprefixed: one release
per cluster, same rationale as Connector/PeerRelay names.
*/}}
{{- define "tailscale-operator.customResourceState.name" -}}
custom-resource-state-exporter
{{- end }}

{{/*
ClusterRole/Binding name. Cluster-scoped, so it includes release and
namespace (same collision concern as OIDC discovery). ClusterRole/Binding
names follow the standard Kubernetes object name limit (253 chars), not
the 63-char DNS label limit that "tailscale-operator.fullname" itself
already applies -- truncating here at 63 again could cut into the
namespace or "-crs" suffix and collide two different releases/namespaces
onto the same name, so trunc at 253 instead, which no realistic
release+namespace pair can reach.
*/}}
{{- define "tailscale-operator.customResourceState.clusterRoleName" -}}
{{- printf "%s-%s-crs" (include "tailscale-operator.fullname" .) .Release.Namespace | trunc 253 | trimSuffix "-" }}
{{- end }}

{{/*
Kyverno-required labels copied from the operator, with application overridden
so GMP PodMonitoring can select this workload without colliding with the
operator's :8080 scrape.
*/}}
{{- define "tailscale-operator.customResourceState.labels" -}}
application: tailscale-custom-resource-state-exporter
{{- $sub := index .Values "tailscale-operator" | default dict }}
{{- range $k, $v := (($sub.operatorConfig | default dict).podLabels | default dict) }}
{{- if ne $k "application" }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
kube-state-metrics Custom Resource State config. Shared by the ConfigMap
and the Deployment checksum so a config change rolls the pods.
*/}}
{{- define "tailscale-operator.customResourceState.config" -}}
kind: CustomResourceStateMetrics
spec:
  resources:
    - groupVersionKind:
        group: tailscale.com
        version: v1alpha1
        kind: Connector
      metricNamePrefix: kube_tailscale_connector
      labelsFromPath:
        name: [metadata, name]
        proxy_class: [spec, proxyClass]
        is_app_connector: [status, isAppConnector]
        is_exit_node: [status, isExitNode]
      metrics:
        - name: status
          help: Connector condition status (True=1, False/Unknown=0).
          each:
            type: Gauge
            gauge:
              path: [status, conditions]
              labelsFromPath:
                type: [type]
                reason: [reason]
              valueFrom: [status]
        - name: replicas
          help: Desired Connector replica count from spec.replicas.
          each:
            type: Gauge
            gauge:
              path: [spec, replicas]
    - groupVersionKind:
        group: tailscale.com
        version: v1alpha1
        kind: PeerRelay
      metricNamePrefix: kube_tailscale_peerrelay
      labelsFromPath:
        name: [metadata, name]
        proxy_class: [spec, proxyClass]
      metrics:
        - name: status
          help: PeerRelay condition status (True=1, False/Unknown=0).
          each:
            type: Gauge
            gauge:
              path: [status, conditions]
              labelsFromPath:
                type: [type]
                reason: [reason]
              valueFrom: [status]
        - name: replicas
          help: Desired PeerRelay replica count from spec.replicas.
          each:
            type: Gauge
            gauge:
              path: [spec, replicas]
{{- end }}
