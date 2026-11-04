#!/usr/bin/env bash
# CI version of the contract gate, so it holds whichever tool or command made the change.
# Usage: check-contracts.sh [base-ref]   (default: origin/main)
set -euo pipefail

base="${1:-origin/main}"
merge_base="$(git merge-base "$base" HEAD)"
fail=0

while IFS=$'\t' read -r area feature; do
  contract="docs/contracts/$feature.md"
  if [ -f "$contract" ]; then
    status="$(sed -n 's/^status:[[:space:]]*\([a-z]*\).*/\1/p' "$contract" | head -n 1)"
    if [ "$status" != "approved" ]; then
      echo "FAIL: $feature changed, but $contract is '$status', not approved"
      fail=1
    fi
  elif ! git cat-file -e "$merge_base:$area/$feature" 2>/dev/null; then
    echo "FAIL: new feature $area/$feature has no contract at $contract"
    fail=1
  fi
done < <(
  git diff --name-only --no-renames "$merge_base" \
    | sed -nE 's#^(lib/features|src/features|src/modules)/([^/]+)/.*#\1\t\2#p' \
    | sort -u
)

[ "$fail" -eq 0 ] && echo "OK: contracts satisfied"
exit "$fail"
