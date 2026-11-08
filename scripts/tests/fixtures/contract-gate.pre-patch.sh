#!/usr/bin/env bash
# Blocks code for a new feature until its contract is approved, and keeps approval human-only.
set -uo pipefail
shopt -s nocasematch

block() { echo "$1" >&2; exit 2; }
command -v jq >/dev/null || block "contract-gate: jq is required. Install it, then retry."

input="$(cat)"
tool="$(jq -r '.tool_name // empty' <<<"$input")"
file="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
[ -n "$file" ] || exit 0

norm() {
  local p="${1//\\//}"
  if [[ "$p" =~ ^/([a-zA-Z])/(.*)$ ]]; then p="${BASH_REMATCH[1]}:/${BASH_REMATCH[2]}"; fi
  if [[ "$p" =~ ^([A-Z]):(.*)$ ]]; then p="$(tr 'A-Z' 'a-z' <<<"${BASH_REMATCH[1]}"):${BASH_REMATCH[2]}"; fi
  printf '%s' "${p%/}"
}
root="$(norm "${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // "."' <<<"$input")}")"
file="$(norm "$file")"
rel="${file#"$root"/}"
if [[ "$(tr 'A-Z' 'a-z' <<<"$file")" == "$(tr 'A-Z' 'a-z' <<<"$root")/"* ]]; then rel="${file:${#root}+1}"; fi
rel="$(sed -E 's#/+#/#g' <<<"$rel")"
[[ "/$rel/" == */../* || "/$rel/" == */./* ]] && block "Use a path without . or .. segments: $rel"

status_of() { sed -n 's/^status:[[:space:]]*\([a-z]*\).*/\1/p' "$1" | head -n 1; }

# The gates themselves: an agent must not be able to loosen what checks it.
if [[ "$rel" =~ ^(\.claude/(hooks/|settings\.json$)|scripts/check-contracts\.sh$|\.github/workflows/agent-gates\.yml$) ]]; then
  block "$rel is a gate, so only Dave edits it. Report the change you think it needs."
fi

# Contracts: only a person approves one, and an approved one reopens before it changes.
# Checks the status the file would actually have after the edit, not just new_string in isolation.
if [[ "$rel" =~ ^docs/contracts/[^/]+\.md$ ]]; then
  status_in() { sed -n 's/^status:[[:space:]]*\([a-z]*\).*/\1/p' <<<"$1" | head -n 1; }
  cur=""; [ -f "$root/$rel" ] && cur="$(cat "$root/$rel")"
  if [ "$tool" = "Write" ]; then
    new="$(jq -r '.tool_input.content // empty' <<<"$input")"
  else
    old="$(jq -r '.tool_input.old_string // empty' <<<"$input")"
    rep="$(jq -r '.tool_input.new_string // empty' <<<"$input")"
    if [ "$(jq -r '.tool_input.replace_all // false' <<<"$input")" = "true" ]; then
      new=${cur//"$old"/"$rep"}
    else
      new=${cur/"$old"/"$rep"}
    fi
  fi
  if [ "$(status_in "$new")" = "approved" ]; then
    [ "$(status_in "$cur")" = "approved" ] \
      && block "$rel is approved. Set status: draft in this same edit, then report what changed."
    block "Only Dave approves a contract. Leave it as status: draft and ask him to review it."
  fi
  exit 0
fi

# Feature code: lib/features/<f>, src/features/<f>, or src/modules/<f>.
if [[ "$rel" =~ ^(lib/features|src/features|src/modules)/([^/]+)/ ]]; then
  area="${BASH_REMATCH[1]}"
  feature="${BASH_REMATCH[2]}"
  contract="docs/contracts/$feature.md"

  if [ -f "$root/$contract" ]; then
    [ "$(status_of "$root/$contract")" = "approved" ] && exit 0
    block "$contract is not approved yet. Stop and ask Dave to review it."
  fi
  [ -d "$root/$area/$feature" ] && exit 0
  block "New feature '$feature' has no contract. Have iron-man write $contract first."
fi
exit 0
