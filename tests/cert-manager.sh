#!/usr/bin/env bash
# Render tests for charts/cert-manager. Downloads the cert-manager chart on first run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$ROOT/charts/cert-manager"
. "$ROOT/tests/lib/helpers.sh"

render() { helm template cert-manager "$CHART" --namespace cert-manager "$@"; }

deps "$CHART"

echo "cert-manager chart"
out=$(render)
issuer=$(echo "$out" | kind_docs ClusterIssuer)
check "renders one ClusterIssuer" "$(echo "$out" | count '^kind: ClusterIssuer$')" "1"
check "ClusterIssuer is letsencrypt-prod" "$(echo "$out" | objects | count '^ClusterIssuer/letsencrypt-prod$')" "1"
check "ClusterIssuer has no namespace" "$(echo "$issuer" | count '^  namespace:')" "0"
check "ClusterIssuer skips dry run until the CRD exists" \
  "$(echo "$issuer" | count 'argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true')" "1"
check "ClusterIssuer is in sync wave 1" "$(echo "$issuer" | count 'argocd.argoproj.io/sync-wave: "1"')" "1"
check "uses the Let's Encrypt production server" \
  "$(echo "$issuer" | count 'server: https://acme-v02.api.letsencrypt.org/directory')" "1"
check "Route53 key id comes from aws-access-key-id" \
  "$(echo "$issuer" | awk '/accessKeyIDSecretRef:/ {getline; print $2}')" "aws-access-key-id"
check "Route53 secret key comes from aws-secret-access-key" \
  "$(echo "$issuer" | awk '/secretAccessKeySecretRef:/ {getline; print $2}')" "aws-secret-access-key"
check "installs the Certificate CRD" "$(echo "$out" | count '^  name: "\{0,1\}certificates.cert-manager.io"\{0,1\}$')" "1"
check "installs the ClusterIssuer CRD" "$(echo "$out" | count '^  name: "\{0,1\}clusterissuers.cert-manager.io"\{0,1\}$')" "1"

finish
