{{- define "messenger.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "messenger.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "messenger.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/part-of: {{ include "messenger.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* 컴포넌트 selector 라벨. 사용: include "messenger.selectorLabels" (dict "ctx" . "component" "backend") */}}
{{- define "messenger.selectorLabels" -}}
app.kubernetes.io/name: {{ include "messenger.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/* 이미지 경로. 사용: include "messenger.image" (dict "ctx" . "image" .Values.backend.image) */}}
{{- define "messenger.image" -}}
{{- $registry := .ctx.Values.global.imageRegistry | default .image.registry -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry .image.repository .image.tag -}}
{{- else -}}
{{- printf "%s:%s" .image.repository .image.tag -}}
{{- end -}}
{{- end -}}

{{- define "messenger.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "messenger.secretName" -}}
{{ include "messenger.fullname" . }}-secret
{{- end -}}

{{/* 기존 Secret 의 값을 유지하고, 없으면 지정값 또는 랜덤값 사용 */}}
{{- define "messenger.secretValue" -}}
{{- $existing := lookup "v1" "Secret" .ctx.Release.Namespace (include "messenger.secretName" .ctx) -}}
{{- if .value -}}
{{- .value -}}
{{- else if and $existing $existing.data (hasKey $existing.data .key) -}}
{{- index $existing.data .key | b64dec -}}
{{- else -}}
{{- randAlphaNum (.length | default 32) -}}
{{- end -}}
{{- end -}}

{{- define "messenger.dbUrl" -}}
{{- if .Values.postgresql.enabled -}}
{{- printf "jdbc:postgresql://%s-postgresql:5432/%s" (include "messenger.fullname" .) .Values.postgresql.database -}}
{{- else -}}
{{- required "postgresql.enabled=false 이면 externalDatabase.url 이 필요합니다." .Values.externalDatabase.url -}}
{{- end -}}
{{- end -}}

{{- define "messenger.redisHost" -}}
{{- if .Values.redis.enabled -}}
{{- printf "%s-redis" (include "messenger.fullname" .) -}}
{{- else -}}
{{- required "redis.enabled=false 이면 externalRedis.host 가 필요합니다." .Values.externalRedis.host -}}
{{- end -}}
{{- end -}}

{{- define "messenger.securityContext" -}}
allowPrivilegeEscalation: false
runAsNonRoot: true
capabilities:
  drop: ["ALL"]
seccompProfile:
  type: RuntimeDefault
{{- end -}}
