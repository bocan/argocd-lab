#!/usr/bin/env bash
# Render tests for charts/metallb. Downloads the MetalLB chart on first run.
set -euo pipefail

CHART="$(cd "$(dirname "$0")/.." && pwd)/charts/metallb"
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (want '$3', got '$2')"; fi; }
count() { grep -c -- "$1" || true; }
# One "Kind/name" line for each rendered object.
objects() { awk '/^kind: /{k=$2} /^  name: /{if(k){print k"/"$2; k=""}}'; }

render() { helm template metallb "$CHART" --namespace metallb-system "$@"; }

[ -d "$CHART/charts" ] || helm dependency build "$CHART" >/dev/null

echo "metallb chart"
out=$(render)
check "renders one IPAddressPool" "$(echo "$out" | count '^kind: IPAddressPool$')" "1"
check "renders one L2Advertisement" "$(echo "$out" | count '^kind: L2Advertisement$')" "1"
check "pool has the LAN address" "$(echo "$out" | count '^    - 192.168.0.50/32$')" "1"
check "pool and advertisement are in sync wave 1" "$(echo "$out" | count 'argocd.argoproj.io/sync-wave: "1"')" "2"
check "FRR-K8s is not deployed" "$(echo "$out" | objects | count '/frr-k8s')" "0"
check "speaker DaemonSet is deployed" "$(echo "$out" | objects | count '^DaemonSet/metallb-speaker$')" "1"
check "controller Deployment is deployed" "$(echo "$out" | objects | count '^Deployment/metallb-controller$')" "1"

if render --set 'ipAddressPool.addresses=null' >/dev/null 2>&1; then
  fail "render without addresses should fail"
else
  pass "render without addresses fails"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
