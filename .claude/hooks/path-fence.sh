#!/usr/bin/env bash
# Keeps an agent inside the files its role owns. Usage: path-fence.sh <architecture|tests|devops|design|perf|database>
set -uo pipefail

block() { echo "$1" >&2; exit 2; }
command -v jq >/dev/null || block "path-fence: jq is required. Install it, then retry."

case "${1:-}" in
  architecture) allowed='^docs/(contracts|adr)/' ;;
  tests) allowed='(^|/)(test|tests|integration_test|e2e|fixtures)/|(_test\.dart|\.(spec|test|e2e-spec)\.[jt]sx?)$' ;;
  devops) allowed='^(\.github/|infra/|deploy/|k8s/|fastlane/|scripts/|docs/ops\.md$|docs/runbooks/|\.env\.example$|\.nvmrc$|\.dockerignore$)|(^|/)(Dockerfile(\.(prod|production|dev|staging|test|ci|local))?|docker-compose[^/]*\.ya?ml)$' ;;
  design) allowed='^docs/(contracts/[^/]+\.md|design/.+)$' ;;
  perf) allowed='^(([^./][^/]*/)*(perf|load)/.+|([^./][^/]*/)*integration_test/(.+/)?[^/]+_perf_test\.dart|([^./][^/]*/)?(\.size-limit\.json|\.?lighthouserc\.(json|js|cjs|ya?ml)))$' ;;
  database) allowed='^([^./][^/]*/)?(drizzle/.+|drizzle\.config\.([cm]?[jt]s|json)|src/(database/.+|([^./][^/]*/)*schema/.+))$' ;;
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
if [[ "$(tr 'A-Z' 'a-z' <<<"$file")" == "$(tr 'A-Z' 'a-z' <<<"$root")/"* ]]; then rel="${file:${#root}+1}"; fi
rel="$(sed -E 's#/+#/#g' <<<"$rel")"
[[ "/$rel/" == */../* || "/$rel/" == */./* ]] && block "Use a path without . or .. segments: $rel"

if [ "$1" = design ] && [[ "$rel" =~ ^docs/contracts/ ]] && [ ! -f "$root/$rel" ]; then
  block "shuri adds design to an existing contract. Have iron-man create $rel first."
fi
[[ "$rel" =~ $allowed ]] && exit 0
block "This agent ($1) may not edit $rel. Report what needs to change instead."