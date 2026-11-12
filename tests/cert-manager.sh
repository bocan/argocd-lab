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

# A 10m CPU limit throttled the controller so much that ACME account
# registration timed out. Print the CPU limit of each Deployment, in millicores.
cpu_limit() {
  echo "$out" | awk -v d="$1" '
    /^kind: / { k = $2 }
    k == "Deployment" && $0 == "  name: " d { m = 1 }
    m && /limits:/ { l = 1 }
    m && l && /cpu:/ { gsub(/"/, "", $2); print $2; exit }'
}
check "controller CPU limit is 200m" "$(cpu_limit cert-manager)" "200m"
check "webhook CPU limit is 100m" "$(cpu_limit cert-manager-webhook)" "100m"
check "cainjector CPU limit is 100m" "$(cpu_limit cert-manager-cainjector)" "100m"

finish
