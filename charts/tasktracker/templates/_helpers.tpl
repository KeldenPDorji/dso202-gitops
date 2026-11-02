{{/*
=============================================================================
File        : charts/tasktracker/templates/_helpers.tpl
Assignment  : DSO202 Assignment 4
Descriptor  : Unit III 3.2 - named templates
Purpose     : Named templates shared by every file in templates/.
=============================================================================
Files whose names begin with an underscore never produce Kubernetes objects.

Every name is prefixed with the chart name, because named templates are global
across a chart and all of its subcharts. Two charts that both defined "labels"
would silently overwrite each other.
*/}}

{{/* tasktracker.name: the chart name, or nameOverride when set. */}}
{{- define "tasktracker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
tasktracker.fullname: the base name every object is derived from.
Truncated to 63 characters, the Kubernetes limit for a DNS label. If the
release name already contains the chart name, it is used alone, so a release
called tasktracker does not produce "tasktracker-tasktracker".
*/}}
{{- define "tasktracker.fullname" -}}
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

{{/* tasktracker.chart: "<name>-<version>" for the helm.sh/chart label.
     SemVer allows "+" in build metadata, which label values may not contain. */}}
{{- define "tasktracker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
tasktracker.environment: the environment name.
config.environment wins; global.environment is the fallback a parent chart
would set. "required" stops rendering with this message when both are empty,
so the chart cannot produce an object without an environment.
*/}}
{{- define "tasktracker.environment" -}}
{{- required "config.environment must be set (dev, staging or prod)" (.Values.config.environment | default .Values.global.environment) }}
{{- end }}

{{/*
tasktracker.selectorLabels: the small, stable set that selectors match on.
These must never change after the first install, because a Deployment's
spec.selector is immutable and a Service's selector decides routing. Each
workload adds its own app.kubernetes.io/component on top of these.
*/}}
{{- define "tasktracker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tasktracker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
tasktracker.labels: the full recommended label set for every object.
It deliberately includes labels that CHANGE between versions - helm.sh/chart
and app.kubernetes.io/version - which is exactly why it is kept separate from
the selector set above.
*/}}
{{- define "tasktracker.labels" -}}
helm.sh/chart: {{ include "tasktracker.chart" . }}
{{ include "tasktracker.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
dso202/environment: {{ include "tasktracker.environment" . | quote }}
{{- end }}

{{/*
tasktracker.image: builds one image reference from the registry, a tier's
image name and its tag, falling back to .Chart.AppVersion when the tag is
empty. Called with a dict so it can take two arguments:
  {{ include "tasktracker.image" (dict "root" . "tier" .Values.backend) }}
*/}}
{{- define "tasktracker.image" -}}
{{- $root := .root -}}
{{- $tier := .tier -}}
{{- printf "%s/%s:%s" $root.Values.image.registry $tier.image ($tier.tag | default $root.Chart.AppVersion) -}}
{{- end }}
