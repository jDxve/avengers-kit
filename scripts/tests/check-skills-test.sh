#!/usr/bin/env bash
# Tests for scripts/check-skills.sh (docs/contracts/kit-skills.md, "Tests").
# Cases: T-K0 to T-K15.
# Usage: check-skills-test.sh      (CHECK_SKILLS overrides the lint path, for mutant runs)
# Builds every fixture in a mktemp root. Never modifies the repo. Needs bash, grep, sed, tr, cksum.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
lint="${CHECK_SKILLS:-$root/scripts/check-skills.sh}"
self="$here/check-skills-test.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-skills-test.XXXXXX")"
case "$tmp" in
  "${TMPDIR:-/tmp}"/check-skills-test.*) ;;
  *) echo "FAIL: unsafe temp dir '$tmp'"; exit 1 ;;
esac
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0; gap=0
ok()   { echo "OK: $1"; pass=$((pass + 1)); }
bad()  { echo "FAIL: $1"; fail=$((fail + 1)); }
known() { echo "KNOWN GAP: $1"; gap=$((gap + 1)); }

git_state() { git -C "$root" status --porcelain 2>/dev/null || true; }
before="$(git_state)"

# Strings built at runtime, so this file holds no dash bytes and no attribution text.
EM="$(printf '\xe2\x80\x94')"
EN="$(printf '\xe2\x80\x93')"
ROBOT="$(printf '\xf0\x9f\xa4\x96')"
CO="$(printf '%s-%s-%s' Co Authored By)"
GEN="$(printf '%s%s %s' Gener ated with)"
CLAUDE="$(printf '%s%s' Cla ude)"
CLAUDE_CODE="$CLAUDE Code"
CHATGPT="$(printf '%s%s' Chat GPT)"
CLURL="https://example.com/agent"

n=0
d=""
out=""
rc=0

put() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

# skill <dir> <name> [body]: a valid SKILL.md in <dir>/.claude/skills/<name>
skill() {
  mkdir -p "$1/.claude/skills/$2"
  printf -- '---\nname: %s\ndescription: Does a thing.\n---\n# %s\n%s\n' "$2" "$2" "${3:-}" > "$1/.claude/skills/$2/SKILL.md"
}
# agent <dir> <name> [skill...]: an agent file, with a skills: list when skills are given
agent() {
  local dir="$1" name="$2"; shift 2
  mkdir -p "$dir/.claude/agents"
  {
    printf -- '---\nname: %s\ndescription: x\n' "$name"
    if [ $# -gt 0 ]; then printf 'skills:\n'; for s in "$@"; do printf '  - %s\n' "$s"; done; fi
    printf -- '---\nBody.\n'
  } > "$dir/.claude/agents/$name.md"
}
# fresh: new tree $d with skills a and c, a reference, and agent b preloading a
fresh() {
  n=$((n + 1)); d="$tmp/c$n"; mkdir -p "$d"
  skill "$d" a 'See `01-x.md`.'
  skill "$d" c
  printf '# X\nText.\n' | put "$d/.claude/skills/a/references/01-x.md"
  agent "$d" b a
}
run() { set +e; out="$(bash "$lint" --root "$1" 2>&1)"; rc=$?; set -e; }
sk() { printf '%s' "$d/.claude/skills/$1"; }

# expect_fail <id> <label> <pattern>: exit 1 and a FAIL line matching the pattern
expect_fail() {
  run "$d"
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -Eq -- "^FAIL: $3"; then ok "$1 $2"
  else bad "$1 $2 (exit $rc, want 1 with FAIL: $3; output: $(printf '%s' "$out" | head -n 3 | tr '\n' '|'))"; fi
}
# expect_pass <id> <label>: exit 0 and an OK line
expect_pass() {
  run "$d"
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^OK: '; then ok "$1 $2"
  else bad "$1 $2 (exit $rc, want 0; output: $(printf '%s' "$out" | head -n 3 | tr '\n' '|'))"; fi
}
# expect_exit <id> <label> <code> <args...>
expect_exit() {
  local id="$1" label="$2" want="$3"; shift 3
  set +e; out="$(bash "$lint" "$@" 2>&1)"; rc=$?; set -e
  if [ "$rc" -eq "$want" ]; then ok "$id $label"; else bad "$id $label (exit $rc, want $want)"; fi
}
# set_skill <name> : replace a/SKILL.md content from stdin
set_skill() { put "$(sk "$1")/SKILL.md"; }

# T-K0
if bash -n "$lint" && bash -n "$self"; then ok "T-K0 bash -n on the lint and the test file"; else bad "T-K0 bash -n failed"; fi
if sed 's/^[[:space:]]*#.*$//' "$lint" | grep -nE '(^|[^[:alnum:]_./-])(find|awk|python3?|perl|curl|wget)([[:space:]]|$)' >/dev/null; then
  bad "T-K0 the lint calls find, awk, python, perl, or curl"
else ok "T-K0 the lint calls no find, awk, python, perl, or curl"; fi

# T-K1
fresh
run "$d"
if [ "$rc" -eq 0 ] && [ "$out" = "OK: 2 skills, 1 agents consistent" ]; then ok "T-K1 clean tree exits 0 with the OK line"
else bad "T-K1 clean tree (exit $rc, output: $out)"; fi

# T-K2
fresh; printf -- '# a\nname: a\ndescription: x\n---\n' | set_skill a
expect_fail T-K2 "no opening ---" 'K1 .*SKILL\.md:1 line 1 is not ---'
fresh; printf -- '---\nname: a\ndescription: x\n# a\n' | set_skill a
expect_fail T-K2 "no closing ---" 'K1 .*has no closing ---'
fresh; printf -- '---\ndescription: x\n---\n' | set_skill a
expect_fail T-K2 "missing name" 'K1 .*name: appears 0 times'
fresh; printf -- '---\nname: other\ndescription: x\n---\n' | set_skill a
expect_fail T-K2 "name differs from folder" "K1 .*name 'other' does not equal folder 'a'"
fresh; printf -- '---\nname: A\ndescription: x\n---\n' | set_skill a
expect_fail T-K2 "uppercase name" "K1 .*name 'A' is not lowercase"
fresh; printf -- '---\nname: a--b\ndescription: x\n---\n' | set_skill a
expect_fail T-K2 "double hyphen name" "K1 .*name 'a--b' is not lowercase"
fresh
long65="$(printf 'a%.0s' $(seq 1 65))"
skill "$d" "$long65"
expect_fail T-K2 "name of 65 characters" 'K1 .*name has 65 characters'
fresh
long64="$(printf 'a%.0s' $(seq 1 64))"
skill "$d" "$long64"
expect_pass T-K2 "name of 64 characters passes"
fresh; printf -- '---\nname: a\n---\n' | set_skill a
expect_fail T-K2 "missing description" 'K1 .*description: appears 0 times'
fresh; printf -- '---\nname: a\ndescription: \n---\n' | set_skill a
expect_fail T-K2 "empty description" 'K1 .*description is empty'
fresh; desc1025="$(printf 'x%.0s' $(seq 1 1025))"
printf -- '---\nname: a\ndescription: %s\n---\n' "$desc1025" | set_skill a
expect_fail T-K2 "description of 1025 characters" 'K1 .*description has 1025 characters'
fresh; desc1024="$(printf 'x%.0s' $(seq 1 1024))"
printf -- '---\nname: a\ndescription: %s\n---\n' "$desc1024" | set_skill a
expect_pass T-K2 "description of 1024 characters passes"
fresh; printf -- '---\nname: a\ndescription: first\n  second\n---\n' | set_skill a
expect_fail T-K2 "two-line description" 'K1 .*description spans more than one line'
fresh; printf -- '---\nname: a\ndescription: >\n  folded\n---\n' | set_skill a
expect_fail T-K2 "folded description" 'K1 .*description spans more than one line'
fresh; printf -- '---\nname: a\ndescription: x\nowner: me\n---\n' | set_skill a
expect_fail T-K2 "unknown key" "K1 .*key 'owner' is not in ALLOWED_KEYS"
fresh; printf -- '---\nname: a\ndescription: x\npaths: src/**\n---\n' | set_skill a
expect_pass T-K2 "paths key passes"
fresh; mkdir -p "$d/.claude/skills/empty"
expect_fail T-K2 "skill folder with no SKILL.md" 'K1 .*skills/empty has no SKILL\.md'

# T-K3
fresh; agent "$d" b missing
expect_fail T-K3 "agent preloads a missing skill" 'K2 .*skills: missing has no'
fresh; agent "$d" b
expect_pass T-K3 "agent with no skills: passes"
fresh; printf -- '---\nname: b\ndescription: x\nskills: [a, c]\n---\n' | put "$d/.claude/agents/b.md"
expect_pass T-K3 "inline skills list of existing skills passes"
fresh; printf -- '---\nname: b\ndescription: x\nskills: [a, nope]\n---\n' | put "$d/.claude/agents/b.md"
expect_fail T-K3 "inline skills list with a missing skill" 'K2 .*skills: nope has no'
fresh; agent "$d" b a missing; sed -i.bak 's/$/\r/' "$d/.claude/agents/b.md"; rm -f "$d/.claude/agents/b.md.bak"
expect_fail T-K3 "CRLF agent file names the missing skill without a CR" 'K2 .*skills: missing has no'
fresh; agent "$d" b a c; sed -i.bak 's/$/\r/' "$d/.claude/agents/b.md"; rm -f "$d/.claude/agents/b.md.bak"
expect_pass T-K3 "CRLF agent file with existing skills passes"

# T-K4
fresh; printf '[gone](references/02-gone.md)\n' >> "$(sk a)/SKILL.md"
expect_fail T-K4 "broken relative link" 'K3 .*SKILL\.md:[0-9]+ references/02-gone\.md does not exist'
fresh; printf '```\n[gone](references/02-gone.md)\n]([^'"'"'"]+)\n```\n' >> "$(sk a)/SKILL.md"
expect_pass T-K4 "broken link inside a fenced code block passes"
fresh; printf '[site](https://example.com/x) [mail](mailto:a@example.com) [top](#top)\n' >> "$(sk a)/SKILL.md"
expect_pass T-K4 "https, mailto, and anchor links pass"
fresh; printf '[part](references/01-x.md#part)\n' >> "$(sk a)/SKILL.md"
expect_pass T-K4 "file.md#part resolves by path"
fresh; printf '[part](references/02-gone.md#part)\n' >> "$(sk a)/SKILL.md"
expect_fail T-K4 "missing file with an anchor fails" 'K3 .*references/02-gone\.md does not exist'
fresh; printf 'Inline `[x](nope.md)` code is not a link.\n' >> "$(sk a)/SKILL.md"
expect_pass T-K4 "link text inside an inline code span passes"
fresh; printf 'See `09-missing.md`.\n' >> "$(sk a)/SKILL.md"
expect_fail T-K4 "backticked reference file name that does not exist" 'K3 .*09-missing\.md does not exist'
fresh; printf 'See `01-x.md`.\n' >> "$(sk c)/SKILL.md"
expect_pass T-K4 "backticked reference found in another skill passes"

# T-K5
fresh; printf 'a %s b\n' "$EM" >> "$(sk a)/references/01-x.md"
expect_fail T-K5 "em dash in a reference" 'K4 .*01-x\.md:[0-9]+ em or en dash'
fresh; printf 'a %s b\n' "$EN" >> "$d/.claude/agents/b.md"
expect_fail T-K5 "en dash in an agent file" 'K4 .*agents/b\.md:[0-9]+ em or en dash'
fresh; printf '```\na %s b\n```\n' "$EM" >> "$(sk a)/references/01-x.md"
expect_fail T-K5 "em dash inside a code block" 'K4 .*01-x\.md:[0-9]+ em or en dash'
fresh; printf 'a %s b\n' "$EM" > "$(sk a)/notes.txt"
expect_fail T-K5 "em dash in a non-markdown file under skills" 'K4 .*notes\.txt:1 em or en dash'
fresh; printf 'a - b -- c\n' >> "$(sk a)/references/01-x.md"
expect_pass T-K5 "hyphens pass"

# T-K6
fresh
{ printf -- '---\nname: a\ndescription: x\n---\n'; i=0; while [ "$i" -lt 96 ]; do printf 'line\n'; i=$((i + 1)); done; } | set_skill a
lines="$(wc -l < "$(sk a)/SKILL.md" | tr -d ' ')"
if [ "$lines" -eq 100 ]; then expect_pass T-K6 "SKILL.md of exactly 100 lines passes"; else bad "T-K6 fixture has $lines lines, want 100"; fi
printf 'line\n' >> "$(sk a)/SKILL.md"
expect_fail T-K6 "SKILL.md of 101 lines" 'K5 .*SKILL\.md has 101 lines, cap 100'
fresh
{ printf -- '---\nname: a\ndescription: x\n---\n'; i=0; while [ "$i" -lt 150 ]; do printf 'line\n'; i=$((i + 1)); done; } > "$(sk a)/references/01-x.md"
expect_pass T-K6 "a reference over 100 lines is not capped"

# T-K7 (K6 attribution)
attr_fail() {
  fresh; printf '%s\n' "$2" >> "$(sk a)/SKILL.md"
  expect_fail T-K7 "$1 in a skill" 'K6 .*SKILL\.md:[0-9]+ attribution line'
}
attr_fail "co-author trailer" "$CO: X <x@example.com>"
attr_fail "co-author trailer lowercase" "$(printf '%s' "$CO: X" | tr 'A-Z' 'a-z')"
attr_fail "generated-with link" "$GEN [$CLAUDE_CODE]($CLURL)"
attr_fail "generated-with plain name" "$GEN $CLAUDE"
attr_fail "robot emoji then generated-with link" "$ROBOT $GEN [$CLAUDE_CODE]($CLURL)"
attr_fail "robot emoji then generated-with unlisted tool (emoji branch only)" "$ROBOT $GEN Acmetool"
attr_fail "generated-with uppercase name" "$(printf '%s %s' GENERATED WITH) $(printf '%s' "$CHATGPT" | tr 'a-z' 'A-Z')"
attr_fail "generated-with an AI assistant" "$GEN an AI assistant"
fresh; printf '%s: X <x@example.com>\n' "$CO" >> "$d/.claude/agents/b.md"
expect_fail T-K7 "co-author trailer in an agent file" 'K6 .*agents/b\.md:[0-9]+ attribution line'
fresh; printf '```\n%s: X <x@example.com>\n```\n' "$CO" >> "$(sk a)/references/01-x.md"
expect_fail T-K7 "co-author trailer inside a code block" 'K6 .*01-x\.md:[0-9]+ attribution line'
fresh; printf '%s %s\n' "$GEN" "$CLAUDE" > "$(sk a)/notes.txt"
expect_fail T-K7 "generated-with name in a non-markdown file" 'K6 .*notes\.txt:1 attribution line'
# K6 regression: legitimate prose with "generated with" must pass
attr_pass() {
  fresh; printf '%s\n' "$2" >> "$(sk a)/references/01-x.md"
  expect_pass T-K7 "$1 passes (K6 regression)"
}
attr_pass "migrations prose" "Migrations are $(printf '%s %s' generated with) \`drizzle-kit generate\`."
attr_pass "types prose" "Types are $(printf '%s %s' generated with) openapi-typescript."
attr_pass "air quotes prose" "Docs $(printf '%s %s' generated with) air quotes."
attr_pass "word starting with ai" "Output $(printf '%s %s' generated with) aim and care."

# T-K8
fresh; mkdir -p "$d/.claude/skills/security-engineering/references"
skill "$d" security-engineering
printf '# X\nNo sources here.\n' | put "$d/.claude/skills/security-engineering/references/01-y.md"
expect_fail T-K8 "sourced skill reference without ## Sources" 'K7 .*01-y\.md has no ## Sources'
printf '# X\n\n## Sources\n\n## Next\ntext\n' | put "$d/.claude/skills/security-engineering/references/01-y.md"
expect_fail T-K8 "empty Sources section" 'K7 .*01-y\.md has an empty ## Sources'
printf '# X\n\n## Sources\n' | put "$d/.claude/skills/security-engineering/references/01-y.md"
expect_fail T-K8 "Sources heading at end of file" 'K7 .*01-y\.md has an empty ## Sources'
printf '# X\n\n## Sources\n\n- OWASP Top 10, 2021, https://owasp.org\n' | put "$d/.claude/skills/security-engineering/references/01-y.md"
expect_pass T-K8 "filled Sources section passes"
fresh; printf '# X\nNo sources here.\n' > "$(sk a)/references/01-x.md"
expect_pass T-K8 "reference in a skill outside SOURCED_SKILLS passes"
fresh; skill "$d" react-standards
printf '# X\nNo sources.\n' | put "$d/.claude/skills/react-standards/references/17-nextjs-app-router.md"
expect_fail T-K8 "single sourced path without ## Sources" 'K7 .*17-nextjs-app-router\.md has no ## Sources'
printf '# X\nNo sources.\n' | put "$d/.claude/skills/react-standards/references/01-other.md"
printf '# X\n## Sources\n- Next.js docs\n' | put "$d/.claude/skills/react-standards/references/17-nextjs-app-router.md"
expect_pass T-K8 "other react-standards references need no Sources"

# T-K9
wf() { printf 'jobs:\n  b:\n    steps:\n      - %s\n' "$1" | put "$(sk a)/assets/wf.yml"; }
fresh; wf 'uses: actions/checkout@v4'
expect_fail T-K9 "uses with a tag" 'K8 .*wf\.yml:[0-9]+ uses: actions/checkout@v4 is not pinned'
fresh; wf 'uses: actions/checkout'
expect_fail T-K9 "uses with no ref" 'K8 .*wf\.yml:[0-9]+ uses: actions/checkout is not pinned'
fresh; wf "uses: actions/checkout@$(printf 'b%.0s' $(seq 1 39))"
expect_fail T-K9 "uses with a 39-character ref" 'K8 .*wf\.yml:[0-9]+ uses: '
fresh; wf "uses: actions/checkout@$(printf 'b%.0s' $(seq 1 40)) # v4"
expect_pass T-K9 "40-hex SHA with a trailing comment passes"
fresh; wf "uses: actions/checkout@$(printf '0%.0s' $(seq 1 40))"
expect_pass T-K9 "zero PIN placeholder passes"
fresh; wf 'uses: ./local'
expect_pass T-K9 "local uses passes"
fresh; wf 'uses: actions/checkout@v4'; mv "$(sk a)/assets/wf.yml" "$(sk a)/assets/wf.yaml"
expect_fail T-K9 ".yaml extension is also checked" 'K8 .*wf\.yaml:'
fresh; wf 'uses: actions/checkout@v4'; mv "$(sk a)/assets/wf.yml" "$(sk a)/assets/wf.txt"
expect_pass T-K9 "non-yaml asset is not checked"

# T-K10
fresh; printf -- '- [ ] SEC-API-01 Check the thing\n' >> "$(sk a)/references/01-x.md"
expect_fail T-K10 "SEC item with no Verify" 'K9 .*01-x\.md:[0-9]+ SEC-API-01 has no Verify:'
fresh; printf -- '- [ ] DB-MIG-02 Check the thing\n' >> "$(sk a)/references/01-x.md"
expect_fail T-K10 "DB-MIG item with no Verify" 'K9 .*01-x\.md:[0-9]+ DB-MIG-02 has no Verify:'
fresh; printf -- '- [ ] SEC-API-01 Check the thing\n  Verify: run it\n' >> "$(sk a)/references/01-x.md"
expect_pass T-K10 "Verify on the next line passes"
fresh; printf -- '- [ ] SEC-API-01 Check the thing. Verify: run it\n' >> "$(sk a)/references/01-x.md"
expect_pass T-K10 "Verify on the same line passes"
fresh; printf -- '- [ ] SEC-API-01 One. Verify: x\n' >> "$(sk a)/references/01-x.md"
printf -- '- [ ] SEC-API-01 Two. Verify: y\n' > "$(sk c)/notes.md"
expect_fail T-K10 "same id in two files" 'K9 .*SEC-API-01 appears twice'
fresh; printf -- '- [ ] SEC-API-01 One. Verify: x\n- [ ] SEC-API-01 Two. Verify: y\n' >> "$(sk a)/references/01-x.md"
expect_fail T-K10 "same id twice in one file" 'K9 .*SEC-API-01 appears twice'
fresh; printf -- '- [ ] SEC-API-01 One. Verify: x\n- [ ] SEC-API-02 Two. Verify: y\n' >> "$(sk a)/references/01-x.md"
expect_pass T-K10 "distinct ids pass"
fresh; printf '```\n- [ ] SEC-API-01 No verify in a fence\n```\n' >> "$(sk a)/references/01-x.md"
expect_pass T-K10 "unverified item inside a fence is skipped"

# T-K11
fresh
expect_exit T-K11 "--root at a missing directory exits 2" 2 --root "$tmp/does-not-exist"
expect_exit T-K11 "unknown flag exits 2" 2 --bogus
expect_exit T-K11 "--root with no value exits 2" 2 --root
mkdir -p "$tmp/noskills"
expect_exit T-K11 "root without .claude/skills exits 2" 2 --root "$tmp/noskills"

# T-K12
fresh
printf -- '---\nname: wrong\ndescription: x\n---\n' | set_skill a
agent "$d" b missing
printf 'a %s b\n' "$EM" >> "$(sk c)/SKILL.md"
printf '%s: X\n' "$CO" >> "$(sk c)/SKILL.md"
printf '[gone](nope.md)\n' >> "$(sk c)/SKILL.md"
run "$d"
all=1
for id in K1 K2 K3 K4 K6; do printf '%s\n' "$out" | grep -q "^FAIL: $id " || { all=0; bad "T-K12 $id missing from a multi-finding run"; }; done
if [ "$rc" -eq 1 ] && [ "$all" -eq 1 ]; then ok "T-K12 all findings reported in one run, exit 1"; elif [ "$rc" -ne 1 ]; then bad "T-K12 exit $rc, want 1"; fi

# T-K13
snap() { (cd "$1" && { find . | sort; find . -type f -exec cksum {} + | sort; }); }
fresh; s1="$(snap "$d")"; run "$d"; s2="$(snap "$d")"
if [ "$s1" = "$s2" ]; then ok "T-K13 clean tree is byte-identical after a run"; else bad "T-K13 clean tree changed during a run"; fi
printf 'a %s b\n[gone](nope.md)\n' "$EM" >> "$(sk a)/SKILL.md"
s1="$(snap "$d")"; run "$d"; s2="$(snap "$d")"
if [ "$s1" = "$s2" ] && [ "$rc" -eq 1 ]; then ok "T-K13 tree with findings is byte-identical after a run"; else bad "T-K13 tree with findings changed during a run"; fi

# T-K14
crlf() { find "$1" -type f -exec sed -i.bak 's/$/\r/' {} + ; find "$1" -name '*.bak' -exec rm -f {} + ; }
fresh; crlf "$d"
expect_pass T-K14 "CRLF clean tree passes"
fresh; printf '[gone](nope.md)\n' >> "$(sk a)/SKILL.md"
printf -- '---\nname: wrong\ndescription: x\n---\n# c\n' | set_skill c
printf -- '- [ ] SEC-API-01 No verify\n' >> "$(sk a)/references/01-x.md"
run "$d"; lf_out="$out"; lf_rc=$rc
crlf "$d"; run "$d"
if [ "$rc" -eq "$lf_rc" ] && [ "$out" = "$lf_out" ] && [ "$rc" -eq 1 ]; then ok "T-K14 CRLF gives the same result as LF"
else bad "T-K14 CRLF differs from LF (lf exit $lf_rc, crlf exit $rc)"; fi

# T-K15
set +e; real_out="$(cd "$root" && bash "$lint" 2>&1)"; real_rc=$?; set -e
if [ "$real_rc" -eq 0 ]; then ok "T-K15 the real kit passes: $real_out"
else bad "T-K15 the real kit fails (exit $real_rc): $(printf '%s' "$real_out" | head -n 5 | tr '\n' '|')"; fi

# The tests only read the repo: git state must be unchanged
after="$(git_state)"
if [ "$before" = "$after" ]; then ok "repo git status --porcelain unchanged"; else bad "repo git status changed during the run"; fi

echo "Summary: $pass ok, $fail fail, $gap known gap"
[ "$fail" -eq 0 ]
