{{- define "common.validations" -}}
{{- required "'.Values.npd.image.repository' is required" .Values.npd.image.repository -}}
{{- end -}}
