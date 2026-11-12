#!/usr/bin/env bash
# Render tests for charts/external-dns. Downloads the external-dns chart on first run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$ROOT/charts/external-dns"
. "$ROOT/tests/lib/helpers.sh"

deps "$CHART"

echo "external-dns chart"
deploy=$(helm template external-dns "$CHART" --namespace external-dns | kind_docs Deployment)
check "renders one Deployment" "$(echo "$deploy" | count '^kind: Deployment$')" "1"
check "uses the aws provider" "$(echo "$deploy" | count '- --provider=aws$')" "1"
check "only manages funderburg.uk" "$(echo "$deploy" | count '- --domain-filter=funderburg.uk$')" "1"
check "reads Ingresses" "$(echo "$deploy" | count '- --source=ingress$')" "1"
check "never deletes records" "$(echo "$deploy" | count '- --policy=upsert-only$')" "1"

# The credentials chain: Secret external-dns, key "credentials", mounted at
# /.aws, so the pod has /.aws/credentials. The AWS SDK reads that file
# because of AWS_SHARED_CREDENTIALS_FILE.
check "mounts Secret external-dns" \
  "$(echo "$deploy" | awk '/secretName:/ {print $2}')" "external-dns"
check "mounts it at /.aws" "$(echo "$deploy" | count 'mountPath: /.aws$')" "1"
check "AWS SDK reads /.aws/credentials" \
  "$(echo "$deploy" | awk '/name: AWS_SHARED_CREDENTIALS_FILE/ {getline; print $2}')" "/.aws/credentials"
check "sealed Secret has the key credentials" \
  "$(grep -c '^    credentials: Ag' "$ROOT/directories/all-secrets/external-dns-sealed-secret.yaml")" "1"

finish
