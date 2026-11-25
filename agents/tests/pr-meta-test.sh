#!/usr/bin/env bash
# Regression test for pr_meta in agents/configmap-agent-config.yaml: the title limit must count characters, not bytes,
# even when the calling step has no UTF-8 locale (LC_ALL=C).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

# Reproduce the agent image, where the step locale is not UTF-8. PR_META_TEST_LC_ALL can run the same test elsewhere.
export LC_ALL="${PR_META_TEST_LC_ALL:-C}"
export LANG="$LC_ALL"

config="agents/configmap-agent-config.yaml"
[ -f "$config" ] || { echo "missing $config" >&2; exit 1; }

# Extract the pr-meta.sh block from the ConfigMap (4-space-indented literal scalar at 2-space key indentation).
pr_meta_script="$(awk '
  /^  pr-meta\.sh: \|/ { inside = 1; next }
  inside && /^  [^ ]/ { inside = 0 }
  inside { sub(/^    /, ""); print }
' "$config")"
[ -n "$pr_meta_script" ] || { echo "could not extract pr-meta.sh from $config" >&2; exit 1; }

# pr_meta hardcodes /workspace/out/pr.txt, so use the real path and restore whatever was there.
out_dir=/workspace/out
mkdir -p "$out_dir"
backup=""
cleanup() {
  if [ -n "$backup" ]; then
    cp "$backup" "$out_dir/pr.txt"
    rm -f "$backup"
  else
    rm -f "$out_dir/pr.txt"
  fi
}
if [ -f "$out_dir/pr.txt" ]; then backup="$(mktemp)"; cp "$out_dir/pr.txt" "$backup"; fi
trap cleanup EXIT

# shellcheck disable=SC1090
source <(printf '%s\n' "$pr_meta_script")

fail() { echo "FAIL: $*" >&2; exit 1; }

# 80 characters of a Conventional Commits title with multi-byte Polish letters: >100 bytes, <=100 characters.
polish_title="feat(bridge): $(printf 'żółć%.0s' {1..16})ąę"
polish_chars="$(python3 -c 'import sys; print(len(sys.argv[1]))' "$polish_title")"
polish_bytes="$(LC_ALL=C; printf '%s' "$polish_title" | wc -c)"
[ "$polish_chars" -le 100 ] || fail "test fixture has $polish_chars characters (expected <=100)"
[ "$polish_bytes" -gt 100 ] || fail "test fixture has $polish_bytes bytes (expected >100)"

printf 'title: %s\nscope: partial\n' "$polish_title" > "$out_dir/pr.txt"
PR_TITLE=""
PR_KEYWORD=""
pr_meta "feat: fallback title"
[ "$PR_TITLE" = "$polish_title" ] || fail "Polish title of $polish_chars chars / $polish_bytes bytes was rejected (got: '$PR_TITLE')"
[ "$PR_KEYWORD" = "Refs" ] || fail "scope handling changed: expected Refs, got '$PR_KEYWORD'"

# A title over 100 characters is still rejected and the fallback title is used.
long_title="feat(bridge): $(printf 'a%.0s' {1..87})"
long_chars="$(python3 -c 'import sys; print(len(sys.argv[1]))' "$long_title")"
[ "$long_chars" -gt 100 ] || fail "test fixture has $long_chars characters (expected >100)"
printf 'title: %s\n' "$long_title" > "$out_dir/pr.txt"
PR_TITLE=""
PR_KEYWORD=""
pr_meta "feat: fallback title" 2>/dev/null
[ "$PR_TITLE" = "feat: fallback title" ] || fail "title of $long_chars chars was accepted (got: '$PR_TITLE')"
[ "$PR_KEYWORD" = "Closes" ] || fail "scope handling changed: expected Closes, got '$PR_KEYWORD'"

# A normal ASCII title within the limit still passes through unchanged.
ascii_title="fix(bridge): keep valid titles"
printf 'title: %s\n' "$ascii_title" > "$out_dir/pr.txt"
PR_TITLE=""
PR_KEYWORD=""
pr_meta "feat: fallback title"
[ "$PR_TITLE" = "$ascii_title" ] || fail "valid ASCII title was rejected (got: '$PR_TITLE')"

echo "PASS: pr_meta counts characters, not bytes"
