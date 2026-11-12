#!/usr/bin/env bash
# Render tests for charts/root-app. Needs only helm, grep and awk.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$ROOT/charts/root-app"
. "$ROOT/tests/lib/helpers.sh"

render() { helm template root-app "$CHART" --namespace argocd "$@"; }
# Application names, sorted, one line.
app_names() { awk '/^kind: Application$/ {a=1} a && /^  name: / {print $2; a=0}' | sort | xargs; }
# Match the list item only, not comments that name the finalizer.
FINALIZER='^    - resources-finalizer.argocd.argoproj.io$'
# Print the one rendered document whose metadata.name is $1.
app_doc() {
  awk -v n="$1" '
    /^---/ { if (m) printf "%s", buf; buf = ""; m = 0; next }
    { buf = buf $0 "\n" }
    $0 == "  name: " n { m = 1 }
    END { if (m) printf "%s", buf }'
}

# Every key directly under `apps:` in values.yaml.
ALL_APPS=$(awk '/^apps:/ {a=1; next} a && /^[^ #]/ {a=0} a && /^  [a-z0-9-]+:$/ {sub(":", ""); print $1}' "$CHART/values.yaml")
# The apps with `enabled: true` in values.yaml.
ENABLED_APPS=$(awk '/^apps:/ {a=1; next} a && /^[^ #]/ {a=0}
  a && /^  [a-z0-9-]+:$/ {app=$1; sub(":", "", app)}
  a && /^    enabled: true$/ {print app}' "$CHART/values.yaml")
ALL_ON=()
for app in $ALL_APPS; do ALL_ON+=(--set "apps.$app.enabled=true"); done
n_apps=$(echo "$ALL_APPS" | wc -w | tr -d ' ')

echo "helm lint"
if helm lint "$CHART" >/dev/null; then pass "chart lints"; else fail "chart lints"; fi

echo "default values ($(echo $ENABLED_APPS) enabled)"
out=$(render)
check "renders root-app and the enabled apps only" "$(echo "$out" | app_names)" \
  "$(printf '%s\n' $ENABLED_APPS root-app | sort | xargs)"
check "argo-cd is enabled" "$(echo "$out" | app_doc argo-cd | count '^kind: Application$')" "1"
check "argo-cd has no finalizer" "$(echo "$out" | app_doc argo-cd | count "$FINALIZER")" "0"
check "root-app has no finalizer" "$(echo "$out" | app_doc root-app | count "$FINALIZER")" "0"
check "argo-cd creates its namespace" "$(echo "$out" | app_doc argo-cd | count 'CreateNamespace=true')" "1"

echo "all $n_apps apps enabled"
out=$(render "${ALL_ON[@]}")
n_kinds=$(echo "$out" | count '^kind: Application$')
check "renders every app plus root-app" "$n_kinds" "$((n_apps + 1))"
check "every Application is in the argocd namespace" "$(echo "$out" | count '^  namespace: argocd$')" "$n_kinds"
check "finalizer on all apps except argo-cd" "$(echo "$out" | count "$FINALIZER")" "$((n_apps - 1))"
check "kube-prometheus-stack uses server-side apply" "$(echo "$out" | count 'ServerSideApply=true')" "1"
check "keycloak keeps selfHeal off" \
  "$(echo "$out" | awk '/^  name: keycloak$/ {k=1} k && /selfHeal:/ {print $2; exit}')" "false"

echo "per-app overrides"
out=$(render --set apps.sealed-secrets.enabled=true --set apps.sealed-secrets.automated=false)
check "automated=false drops the automated block" \
  "$(echo "$out" | awk '/^  name: sealed-secrets$/ {k=1} k && /^kind:/ {k=0} k' | count 'automated:')" "0"

out=$(render --set apps.argo-cd.namespaceLabels.team=lab)
check "namespaceLabels become managedNamespaceMetadata labels" \
  "$(echo "$out" | app_doc argo-cd | awk '/managedNamespaceMetadata:/ {m=1} m && /team:/ {print $2}')" "lab"
check "no managedNamespaceMetadata without namespaceLabels" \
  "$(echo "$out" | app_doc root-app | count managedNamespaceMetadata)" "0"

echo "missing path fails the render"
if render --set apps.broken.enabled=true >/dev/null 2>&1; then
  fail "render without path should fail"
else
  pass "render without path fails"
fi

finish
