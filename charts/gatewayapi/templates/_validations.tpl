{{/*
Public-gateway Cloud Armor enforcement. For every enabled HTTPRoute that has a
parentRef with "public" in its name, each backendRef must point at a Service
named `*-ca-pub-gw` or `*-ca-pub-gw-<n>`, and that Service must be the target
of an enabled GCPBackendPolicy with a non-empty securityPolicy. An empty string
would detach Cloud Armor and an omitted key leaves it unmanaged, so neither
counts. This check is always on and cannot be disabled.
*/}}
{{- define "gatewayapi.validatePublicRoutes" -}}
{{- $protected := dict }}
{{- if .Values.gcpBackendPolicies.enabled }}
{{- range .Values.gcpBackendPolicies.items }}
{{- if and (ne .enabled false) (dig "spec" "default" "securityPolicy" "" .) }}
{{- $_ := set $protected .spec.targetRef.name true }}
{{- end }}
{{- end }}
{{- end }}
{{- range $route := .Values.routes.items }}
{{- if and (ne $route.enabled false) (eq (default "HTTPRoute" $route.kind) "HTTPRoute") }}
{{- $publicParent := "" }}
{{- range $route.spec.parentRefs }}
{{- if and (not $publicParent) (contains "public" (toString .name)) }}
{{- $publicParent = .name }}
{{- end }}
{{- end }}
{{- if $publicParent }}
{{- range $route.spec.rules }}
{{- range .backendRefs }}
{{- if not (regexMatch "-ca-pub-gw(-[0-9]+)?$" .name) }}
{{- fail (printf "Route '%s' attaches to public Gateway '%s', so backendRef '%s' must end with '-ca-pub-gw' or '-ca-pub-gw-<n>'" $route.name $publicParent .name) }}
{{- end }}
{{- if not (hasKey $protected .name) }}
{{- fail (printf "Route '%s' attaches to public Gateway '%s', so Service '%s' needs an enabled gcpBackendPolicies item targeting it with a non-empty spec.default.securityPolicy" $route.name $publicParent .name) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
