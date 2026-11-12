# Shared helpers for the render tests. Source this file; do not run it.
# It is in a subfolder so that `make test` (tests/*.sh) does not run it.

failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (want '$3', got '$2')"; fi; }
count() { grep -c -- "$1" || true; }
# One "Kind/name" line for each rendered object.
objects() { awk '/^kind: /{k=$2} /^  name: /{if(k){print k"/"$2; k=""}}'; }
# Print every rendered document of kind $1.
kind_docs() {
  awk -v k="kind: $1" '
    /^---/ { if (m) printf "%s", buf; buf = ""; m = 0; next }
    { buf = buf $0 "\n" }
    $0 == k { m = 1 }
    END { if (m) printf "%s", buf }'
}
# Download chart dependencies when the pinned version is not there yet, so a
# version bump in Chart.yaml does not test against an old download. Chart.lock
# is gitignored and goes stale, so remove it first.
deps() {
  local want
  want=$(awk '/^dependencies:/ {d=1} d && /^ +- name: / {n=$3} d && /^ +version: / {print n"-"$2".tgz"; exit}' "$1/Chart.yaml")
  [ -f "$1/charts/$want" ] && return 0
  rm -rf "$1/charts" "$1/Chart.lock"
  helm dependency build "$1" >/dev/null
  rm -f "$1/Chart.lock"
}

finish() {
  if [ "$failures" -ne 0 ]; then
    echo "$failures test(s) failed"
    exit 1
  fi
  echo "all tests passed"
}
