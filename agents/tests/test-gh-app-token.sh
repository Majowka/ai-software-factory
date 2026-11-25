#!/usr/bin/env bash
# Regression test for pem_normalize in gh-app-token.sh (agents/configmap-agent-config.yaml).
# Run from the repository root: bash agents/tests/test-gh-app-token.sh
set -uo pipefail
cm=agents/configmap-agent-config.yaml
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# Extract the real pem_normalize function from the gh-app-token.sh block
sed -n '/^  gh-app-token.sh: |/,/^  [a-z-]*\.sh: |\|^  # /p' "$cm" | sed -n '/^    pem_normalize() {/,/^    }/p' | sed -E 's/^    //' > "$tmp/fn.sh"
[ -s "$tmp/fn.sh" ] || { echo "cannot extract pem_normalize"; exit 2; }
# shellcheck disable=SC1090
source "$tmp/fn.sh"

openssl genrsa -traditional -out "$tmp/p1.pem" 2048 2>/dev/null
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$tmp/p8.pem" 2>/dev/null
body() { grep -v -- '-----' "$1" | tr -d '\n'; }
fail=0
check() {
  if printf 'x' | openssl dgst -sha256 -sign <(pem_normalize "$2") >/dev/null 2>&1; then
    echo "ok   $1"
  else
    echo "FAIL $1"; fail=1
  fi
}
for t in p1 p8; do
  f="$tmp/$t.pem"
  check "$t multi-line PEM" "$(cat "$f")"
  check "$t one-line PEM with spaces" "$(tr '\n' ' ' < "$f")"
  check "$t one-line PEM with literal \\n" "$(awk '{printf "%s\\n",$0}' "$f")"
  check "$t body only" "$(body "$f")"
done
exit $fail
