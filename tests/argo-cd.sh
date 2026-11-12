#!/usr/bin/env bash
# Render tests for charts/argo-cd. Downloads the Argo CD chart on first run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$ROOT/charts/argo-cd"
. "$ROOT/tests/lib/helpers.sh"

deps "$CHART"

echo "argo-cd chart"
ingress=$(helm template argo-cd "$CHART" --namespace argocd | kind_docs Ingress)
check "renders one Ingress" "$(echo "$ingress" | count '^kind: Ingress$')" "1"
check "Ingress uses the traefik class" "$(echo "$ingress" | count 'ingressClassName: traefik')" "1"
check "Ingress asks letsencrypt-prod for a certificate" \
  "$(echo "$ingress" | count 'cert-manager.io/cluster-issuer: "\{0,1\}letsencrypt-prod"\{0,1\}$')" "1"
# Two TLS entries for one host make cert-manager issue two certificates.
check "Ingress has one TLS secret" "$(echo "$ingress" | count 'secretName:')" "1"
check "TLS secret is argocd-server-tls" \
  "$(echo "$ingress" | awk '/secretName:/ {print $2}')" "argocd-server-tls"

finish
