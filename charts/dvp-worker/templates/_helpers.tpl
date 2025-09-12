{{- define "dvp-worker.fullname" -}}
{{- printf "%s-%s" .Release.Name "dvp-worker" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "dvp-worker.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "dvp-worker.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
