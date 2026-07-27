{{/*
Shared naming helpers. Defined once at the parent chart — Helm merges parent
+ subchart templates into a single namespace before rendering, so
charts/backend and charts/frontend's own templates can call these too
(that's why they reference "project.fullname", not their own prefix).
*/}}

{{- define "project.name" -}}
{{ .Chart.Name }}
{{- end -}}

{{- define "project.fullname" -}}
{{ .Release.Name }}
{{- end -}}
