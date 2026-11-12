#!/usr/bin/env bash
# Render tests for charts/csi-driver-nfs. Downloads the csi-driver-nfs chart on first run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$ROOT/charts/csi-driver-nfs"
. "$ROOT/tests/lib/helpers.sh"

render() { helm template csi-driver-nfs "$CHART" --namespace kube-system "$@"; }

deps "$CHART"

echo "csi-driver-nfs chart"
out=$(render)
sc=$(echo "$out" | kind_docs StorageClass)
secret=$(echo "$out" | kind_docs Secret)
param() { echo "$sc" | awk -v k="$1:" '$1 == k {v=$2; gsub(/"/, "", v); print v}'; }

check "registers the CSI driver" "$(echo "$out" | objects | count '^CSIDriver/nfs.csi.k8s.io$')" "1"
check "runs the controller" "$(echo "$out" | objects | count '^Deployment/csi-nfs-controller$')" "1"
check "runs the node plugin on every node" "$(echo "$out" | objects | count '^DaemonSet/csi-nfs-node$')" "1"
# No VolumeSnapshot CRDs in this cluster, so no snapshotter sidecar.
check "no snapshotter sidecar" "$(echo "$out" | count 'name: csi-snapshotter$')" "0"
check "no snapshot controller" "$(echo "$out" | objects | count '/snapshot-controller$')" "0"

echo "StorageClass"
check "is named nfs-client" "$(echo "$out" | objects | count '^StorageClass/nfs-client$')" "1"
check "uses the NFS CSI driver" "$(echo "$sc" | awk '/^provisioner:/ {print $2}')" "nfs.csi.k8s.io"
check "points at the NAS" "$(param server)" "192.168.0.55"
check "uses the pi-cluster share" "$(param share)" "/volume1/pi-cluster"
check "names folders after the PVC" "$(param subDir)" '${pvc.metadata.namespace}-${pvc.metadata.name}'
check "archives folders on delete" "$(param onDelete)" "archive"
check "mounts with NFSv3" "$(echo "$sc" | count '^  - nfsvers=3$')" "1"
check "mounts hard" "$(echo "$sc" | count '^  - hard$')" "1"
check "is not the default class" "$(echo "$sc" | count 'is-default-class')" "0"

echo "mount-options Secret"
check "StorageClass names the Secret" "$(param csi.storage.k8s.io/provisioner-secret-name)" "mount-options"
check "StorageClass looks in the release namespace" \
  "$(param csi.storage.k8s.io/provisioner-secret-namespace)" "kube-system"
check "Secret is in the release namespace" "$(echo "$secret" | awk '/^  namespace:/ {print $2}')" "kube-system"
# The delete mount must use the same options as the normal mount.
check "Secret options match the StorageClass" \
  "$(echo "$secret" | awk '/mountOptions:/ {v=$2; gsub(/"/, "", v); print v}')" \
  "$(echo "$sc" | awk '/^mountOptions:/ {m=1; next} m && /^  - / {printf "%s%s", s, $2; s=","}')"

if render --set nfs.server=null >/dev/null 2>&1; then
  fail "render without nfs.server should fail"
else
  pass "render without nfs.server fails"
fi

finish
