#!/usr/bin/env bash
# Static checks on the agent files (docs/contracts/kit-extra-agents.md, "Tests").
# Cases: T-A1 to T-A5, T-A7 to T-A17. T-A6 is retired and never built.
# Usage: agent-files.sh      (KIT_ROOT overrides the repo root, for broken-copy checks)
# Reads only. Needs bash, grep, sed, jq.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${KIT_ROOT:-$(cd "$here/../.." && pwd)}"
agents="$root/.claude/agents"
hook="$root/.claude/hooks/path-fence.sh"
settings="$root/.claude/settings.json"

command -v jq >/dev/null || { echo "FAIL: jq is required"; exit 1; }

pass=0; fail=0; gap=0
ok()   { echo "OK: $1"; pass=$((pass + 1)); }
bad()  { echo "FAIL: $1"; fail=$((fail + 1)); }
known() { echo "KNOWN GAP: $1"; gap=$((gap + 1)); }

# frontmatter <file>: lines between the first two --- lines
frontmatter() { awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$1"; }
fm_value() { frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1; }
tools_of() { fm_value "$1" tools; }
desc_of() { fm_value "$1" description; }
# has_tool <file> <name>: exact item in the tools list
has_tool() { tools_of "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -Fxq -- "$2"; }
tools_contain() { tools_of "$1" | grep -Fq -- "$2"; }
has_fence() { grep -Fq "path-fence.sh $2" "$1"; }
skills_of() { frontmatter "$1" | awk '/^skills:/{on=1;next} on&&/^  - /{sub(/^  - /,"");print;next} on{on=0}'; }

# check_absent_tools <id> <agent> <tool>...
absent_tools() {
  local id="$1" a="$2"; shift 2
  local f="$agents/$a.md" t
  for t in "$@"; do
    if tools_contain "$f" "$t"; then bad "$id $a tools must not contain $t"; else ok "$id $a tools has no $t"; fi
  done
}
desc_has() {
  local id="$1" a="$2" s="$3"
  if desc_of "$agents/$a.md" | grep -Fq -- "$s"; then ok "$id $a description contains '$s'"
  else bad "$id $a description lacks '$s'"; fi
}

# T-A1
want="$(ls "$agents" | sed -n 's/\.md$//p' | grep -vx captain-america | sort | tr '\n' ' ')"
have="$(sed -n 's/^tools:.*Agent(\([^)]*\)).*/\1/p' "$agents/captain-america.md" | tr ',' '\n' | sed 's/[[:space:]]//g' | sort | tr '\n' ' ')"
if [ "$want" = "$have" ] && [ -n "$have" ]; then ok "T-A1 Agent(...) names match agent files"
else bad "T-A1 Agent(...) has [$have] but agent files are [$want]"; fi

# T-A2
for f in "$agents"/*.md; do
  b="$(basename "$f" .md)"; n="$(fm_value "$f" name)"
  if [ "$n" = "$b" ]; then ok "T-A2 $b name matches basename"; else bad "T-A2 $b has name: '$n'"; fi
done

# T-A3
profiles="$(sed -n 's/^  \([a-z]*\)) allowed=.*/\1/p' "$hook")"
[ -n "$profiles" ] || bad "T-A3 found no profiles in the hook case"
for f in "$agents"/*.md; do
  for p in $(grep -o 'path-fence\.sh [a-z]*' "$f" | sed 's/^path-fence\.sh //' | sort -u); do
    if printf '%s\n' "$profiles" | grep -Fxq -- "$p"; then ok "T-A3 $(basename "$f") profile '$p' exists in hook"
    else bad "T-A3 $(basename "$f") uses profile '$p' that is not in the hook case"; fi
  done
done

# T-A4 (shuri)
absent_tools T-A4 shuri Bash NotebookEdit use_figma generate_figma_design create_new_file upload_assets add_code_connect_map
if has_fence "$agents/shuri.md" design; then ok "T-A4 shuri has the design fence hook"; else bad "T-A4 shuri lacks the design fence hook"; fi

# T-A5
desc_has T-A5 shuri "UI/UX designer only"
desc_has T-A5 shuri "Not a general assistant"

# T-A7 (black-panther)
absent_tools T-A7 black-panther Write Edit NotebookEdit

# T-A8
for e in 'Bash(npm audit fix*)' 'Bash(pnpm audit --fix*)'; do
  if jq -e --arg e "$e" '.permissions.deny | index($e)' "$settings" >/dev/null; then ok "T-A8 deny has $e"; else bad "T-A8 deny lacks $e"; fi
done

# T-A9 and T-A10 file set
files=""
for a in shuri black-panther quicksilver vision ant-man spider-man captain-america black-widow hawkeye thor iron-man; do
  files="$files $agents/$a.md"
done
files="$files $root/README.md $root/docs/team.md $root/CHANGELOG.md $root/docs/contracts/kit-extra-agents.md"

emdash="$(printf '\342\200\224')"; endash="$(printf '\342\200\223')"
for f in $files; do
  if [ ! -f "$f" ]; then bad "T-A9 missing file ${f#"$root"/}"; continue; fi
  if grep -Fq -e "$emdash" -e "$endash" "$f"; then bad "T-A9 ${f#"$root"/} has an em or en dash"; else ok "T-A9 ${f#"$root"/} has no em or en dash"; fi
done

# T-A10: strings built at runtime; lines where they sit inside backticks are skipped
s1="$(printf '%s%s' 'Co-Authored' '-By')"; s2="$(printf '%s %s' 'Generated' 'with')"
for f in $files; do
  [ -f "$f" ] || continue
  hit=0
  for s in "$s1" "$s2"; do
    if grep -F -- "$s" "$f" | sed 's/`[^`]*`//g' | grep -Fq -- "$s"; then hit=1; fi
  done
  if [ "$hit" -eq 0 ]; then ok "T-A10 ${f#"$root"/} has no attribution line"; else bad "T-A10 ${f#"$root"/} has an attribution line"; fi
done

# T-A11 (vision)
absent_tools T-A11 vision Write Edit NotebookEdit 'Agent('

# T-A12
desc_has T-A12 vision "Requirements and analysis only"
desc_has T-A12 vision "Not a general assistant"

# T-A13 (ant-man)
if has_fence "$agents/ant-man.md" database; then ok "T-A13 ant-man has the database fence hook"; else bad "T-A13 ant-man lacks the database fence hook"; fi
if skills_of "$agents/ant-man.md" | grep -Fxq database-drizzle; then ok "T-A13 ant-man skills holds database-drizzle"
elif [ ! -f "$root/.claude/skills/database-drizzle/SKILL.md" ]; then
  known "T-A13 ant-man skills lacks database-drizzle; the skill is not shipped yet (kit-skills.md)"
else bad "T-A13 ant-man skills lacks database-drizzle although the skill exists"; fi

# T-A14
for sub in push migrate pull studio; do
  for e in "Bash(npx drizzle-kit $sub*)" "Bash(drizzle-kit $sub*)"; do
    if jq -e --arg e "$e" '.permissions.deny | index($e)' "$settings" >/dev/null; then ok "T-A14 deny has $e"; else bad "T-A14 deny lacks $e"; fi
  done
done
if jq -e '.permissions.deny | index("Bash(psql*)")' "$settings" >/dev/null; then ok "T-A14 deny has Bash(psql*)"; else bad "T-A14 deny lacks Bash(psql*)"; fi

# T-A15 (spider-man)
absent_tools T-A15 spider-man Write Edit NotebookEdit

# T-A16
desc_has T-A16 spider-man "Exploratory tester only"
desc_has T-A16 spider-man "never patches"

# T-A17
desc_has T-A17 black-panther "never against a live or shared system"

# T-A18: the frontmatter of every agent and skill file parses as real YAML
# (regression: an unquoted description containing ': ' made Claude Code refuse to load spider-man)
if command -v ruby >/dev/null 2>&1; then
  for f in "$agents"/*.md "$root"/.claude/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    rel="${f#"$root"/}"
    if err="$(ruby -ryaml -e 'fm = File.read(ARGV[0])[/\A---\r?\n(.*?)\r?\n---\r?\n/m, 1] or abort("no frontmatter"); YAML.safe_load(fm)' "$f" 2>&1)"; then
      ok "T-A18 $rel frontmatter parses as YAML"
    else
      bad "T-A18 $rel frontmatter does not parse as YAML: $(printf '%s' "$err" | head -n 1)"
    fi
  done
else
  known "T-A18 ruby is not installed; frontmatter YAML parsing not checked"
fi

echo "Summary: $pass ok, $fail fail, $gap known gap"
[ "$fail" -eq 0 ]
