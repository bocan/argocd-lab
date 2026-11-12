#!/usr/bin/env bash
# Render tests for charts/sealed-secrets and the SealedSecret folders.
# Downloads the sealed-secrets chart on first run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$ROOT/charts/sealed-secrets"
. "$ROOT/tests/lib/helpers.sh"

deps "$CHART"

echo "sealed-secrets chart"
out=$(helm template sealed-secrets "$CHART" --namespace sealed-secrets)
# kubeseal --controller-name sealed-secrets needs this exact Service name.
check "controller Service is sealed-secrets" "$(echo "$out" | objects | count '^Service/sealed-secrets$')" "1"
check "controller Deployment is sealed-secrets" "$(echo "$out" | objects | count '^Deployment/sealed-secrets$')" "1"

echo "all-secrets folder"
apps=$(helm template root-app "$ROOT/charts/root-app" --namespace argocd)
if ! echo "$apps" | grep -qx '  name: all-secrets'; then
  pass "all-secrets is off, so the namespace checks are skipped"
  finish
  exit 0
fi
# Each SealedSecret must target a namespace whose app is enabled in root-app.
enabled_ns=$(echo "$apps" | awk '/^kind: Application$/ {a=1} a && /^    namespace: / {print $2}' | sort -u)
for f in "$ROOT"/directories/all-secrets/*.yaml; do
  ns=$(awk '/^metadata:/ {m=1} m && /^  namespace: / {print $2; exit}' "$f")
  name=$(basename "$f")
  if echo "$enabled_ns" | grep -qx -- "$ns"; then
    pass "$name targets enabled namespace $ns"
  else
    fail "$name targets $ns, but no enabled app deploys there"
  fi
done

finish
