#!/usr/bin/env bash
# Render tests for charts/root-app. Needs only helm, grep and awk.
set -euo pipefail

CHART="$(cd "$(dirname "$0")/.." && pwd)/charts/root-app"
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (want '$3', got '$2')"; fi; }

render() { helm template root-app "$CHART" --namespace argocd "$@"; }
# Application names, sorted, one line.
app_names() { awk '/^kind: Application$/ {a=1} a && /^  name: / {print $2; a=0}' | sort | xargs; }
count() { grep -c -- "$1" || true; }
# Match the list item only, not comments that name the finalizer.
FINALIZER='^    - resources-finalizer.argocd.argoproj.io$'

# Every key directly under `apps:` in values.yaml.
ALL_APPS=$(awk '/^apps:/ {a=1; next} a && /^[^ #]/ {a=0} a && /^  [a-z0-9-]+:$/ {sub(":", ""); print $1}' "$CHART/values.yaml")
ALL_ON=()
for app in $ALL_APPS; do ALL_ON+=(--set "apps.$app.enabled=true"); done
n_apps=$(echo "$ALL_APPS" | wc -w | tr -d ' ')

echo "helm lint"
if helm lint "$CHART" >/dev/null; then pass "chart lints"; else fail "chart lints"; fi

echo "default values (only argo-cd enabled)"
out=$(render)
check "renders root-app and argo-cd only" "$(echo "$out" | app_names)" "argo-cd root-app"
check "no resources-finalizer anywhere" "$(echo "$out" | count "$FINALIZER")" "0"
check "argo-cd creates its namespace" "$(echo "$out" | count 'CreateNamespace=true')" "2"

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

echo "missing path fails the render"
if render --set apps.broken.enabled=true >/dev/null 2>&1; then
  fail "render without path should fail"
else
  pass "render without path fails"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
