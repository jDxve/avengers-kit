#!/usr/bin/env bash
# Keeps an agent inside the files its role owns. Usage: path-fence.sh <architecture|tests|devops>
set -uo pipefail

block() { echo "$1" >&2; exit 2; }
command -v jq >/dev/null || block "path-fence: jq is required. Install it, then retry."

case "${1:-}" in
  architecture) allowed='^docs/(contracts|adr)/' ;;
  tests) allowed='(^|/)(test|tests|integration_test|e2e|fixtures)/|(_test\.dart|\.(spec|test|e2e-spec)\.[jt]sx?)$' ;;
  devops) allowed='^(\.github/|infra/|deploy/|k8s/|fastlane/|scripts/|docs/ops\.md$|docs/runbooks/|\.env\.example$|\.nvmrc$|\.dockerignore$)|(^|/)(Dockerfile(\.(prod|production|dev|staging|test|ci|local))?|docker-compose[^/]*\.ya?ml)$' ;;
  *) block "path-fence: unknown profile '${1:-}'." ;;
esac

input="$(cat)"
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

[[ "$rel" =~ $allowed ]] && exit 0
block "This agent ($1) may not edit $rel. Report what needs to change instead."
