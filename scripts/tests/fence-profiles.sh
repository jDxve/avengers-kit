#!/usr/bin/env bash
# Tests for .claude/hooks/path-fence.sh (docs/contracts/kit-extra-agents.md, "Tests").
# Cases: T-F0, T-F1, T-F3, T-F4, T-F5, T-F6. T-F2 is retired and never built.
# Also T-F7 (path-fence regression: repeated slashes, U+017F and U+212A folding, a root under a
# tests/ folder, canonical in-role allows, exit code and message per profile).
# Usage: fence-profiles.sh
#   KIT_ROOT    overrides the repo root, for broken-copy checks
#   FENCE       hook under test (default: <root>/.claude/hooks/path-fence.sh), so a proposed fence runs before it is applied
#   FENCE_BASH  shell that runs it (default: bash on PATH)
# Reads the repo; writes only inside a temp dir that is removed on exit.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${KIT_ROOT:-$(cd "$here/../.." && pwd)}"
hook="${FENCE:-$root/.claude/hooks/path-fence.sh}"
FENCE_BASH="${FENCE_BASH:-bash}"
# TMPDIR may end in a slash (macOS does), which would put a // in every fixture path.
tbase="${TMPDIR:-/tmp}"; tbase="${tbase%/}"
tmp="$(mktemp -d "$tbase/fence-profiles.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

command -v jq >/dev/null || { echo "FAIL: jq is required"; exit 1; }
[ -f "$hook" ] || { echo "FAIL: $hook not found"; exit 1; }
echo "fence: $hook"
echo "shell: $FENCE_BASH ($("$FENCE_BASH" --version | head -n 1)), jq: $(jq --version)"

pass=0; fail=0; gap=0
ok()   { echo "OK: $1"; pass=$((pass + 1)); }
bad()  { echo "FAIL: $1"; fail=$((fail + 1)); }
known() { echo "KNOWN GAP: $1"; gap=$((gap + 1)); }

git_state() { git -C "$root" status --porcelain 2>/dev/null || true; }
before="$(git_state)"

# run_hook <profile> <file_path> [project_dir]  -> sets rc, err
run_hook() {
  local profile="$1" path="$2" proj="${3:-$tmp}"
  rc=0
  err="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$path" "$proj" \
    | CLAUDE_PROJECT_DIR="$proj" "$FENCE_BASH" "$hook" "$profile" 2>&1 >/dev/null)" || rc=$?
}

# check <id> <profile> <allow|block> <relpath>
check() {
  local id="$1" profile="$2" want="$3" rel="$4" wantrc
  [ "$want" = allow ] && wantrc=0 || wantrc=2
  run_hook "$profile" "$tmp/$rel"
  if [ "$rc" -eq "$wantrc" ]; then ok "$id $profile $want $rel"
  else bad "$id $profile expected $want ($wantrc) got exit $rc for $rel: $err"; fi
}

mkdir -p "$tmp/docs/contracts/sub"
: > "$tmp/docs/contracts/orders.md"
: > "$tmp/docs/contracts/sub/x.md"
: > "$tmp/docs/contracts/x.txt"

# T-F0
for p in nonsense ""; do
  rc=0
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/a.md"}}' "$tmp" \
    | CLAUDE_PROJECT_DIR="$tmp" "$FENCE_BASH" "$hook" "$p" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then ok "T-F0 profile '$p' exits 2"; else bad "T-F0 profile '$p' expected exit 2 got $rc"; fi
done
rc=0
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/a.md"}}' "$tmp" \
  | CLAUDE_PROJECT_DIR="$tmp" "$FENCE_BASH" "$hook" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then ok "T-F0 no profile argument exits 2"; else bad "T-F0 no profile argument expected exit 2 got $rc"; fi

# T-F1 (design, A.2)
for r in docs/contracts/orders.md docs/design/tokens.md docs/design/orders/flow.md; do check T-F1 design allow "$r"; done
for r in docs/contracts/new-thing.md docs/contracts/sub/x.md docs/contracts/x.txt docs/adr/014-x.md \
         docs/designs/x.md docs/design lib/features/orders/presentation/ui/a.dart \
         src/features/orders/ui/a.tsx README.md .claude/agents/shuri.md; do check T-F1 design block "$r"; done
run_hook design "$tmp/docs/contracts/new-thing.md"
case "$err" in
  *"shuri adds design to an existing contract. Have iron-man create docs/contracts/new-thing.md first."*) ok "T-F1 design new-contract message" ;;
  *) bad "T-F1 design new-contract message wrong: $err" ;;
esac

# T-F3 (perf, D.2)
for r in perf/budgets.json web/perf/checkout.ts load/orders.js backend/load/orders.js \
         integration_test/startup_perf_test.dart mobile/integration_test/scroll_perf_test.dart \
         .size-limit.json web/.size-limit.json lighthouserc.json .lighthouserc.yml; do check T-F3 perf allow "$r"; done
for r in e2e/checkout.spec.ts playwright.config.ts test/orders.e2e-spec.ts integration_test/app_test.dart \
         package.json lib/main.dart src/features/x/ui/a.tsx .claude/hooks/perf/a.sh .claude/skills/x/perf/a.md \
         .github/workflows/perf/x.yml scripts/perf.sh a/b/.size-limit.json perf; do check T-F3 perf block "$r"; done

# T-F4 (regression)
check T-F4 architecture allow docs/contracts/x.md
check T-F4 architecture block lib/x.dart
check T-F4 tests allow test/a_test.dart
check T-F4 tests allow e2e/checkout.spec.ts
check T-F4 tests block lib/a.dart
check T-F4 devops allow .github/workflows/ci.yml
check T-F4 devops block src/main.ts

# T-F5 (path forms): backslash with upper-case drive, and /c/ form, against root C:\proj
winroot='C:\proj'
for pair in 'design|docs\design\tokens.md' 'perf|perf\budgets.json' 'database|drizzle\0001_init.sql'; do
  profile="${pair%%|*}"; wrel="${pair#*|}"; urel="${wrel//\\//}"
  run_hook "$profile" "C:\\proj\\$wrel" "$winroot"
  if [ "$rc" -eq 0 ]; then ok "T-F5 $profile backslash upper-case drive allowed"; else bad "T-F5 $profile backslash form blocked: $err"; fi
  run_hook "$profile" "/c/proj/$urel" "$winroot"
  if [ "$rc" -eq 0 ]; then ok "T-F5 $profile /c/ form allowed"; else bad "T-F5 $profile /c/ form blocked: $err"; fi
done
# b4 dot segments: must be blocked; allowed means b4 is not applied, a known gap
for pair in 'design|docs/design/../../lib/x.dart' 'perf|perf/../lib/main.dart' 'database|drizzle/../../.claude/hooks/x.sh'; do
  profile="${pair%%|*}"; rel="${pair#*|}"
  run_hook "$profile" "$tmp/$rel"
  if [ "$rc" -eq 2 ]; then ok "T-F5 $profile blocks $rel"
  elif [ "$rc" -eq 0 ]; then known "T-F5 $profile allows $rel (b4 path hardening not applied)"
  else bad "T-F5 $profile unexpected exit $rc for $rel"; fi
done

# T-F6 (database, F.2)
for r in drizzle/0001_init.sql drizzle/meta/_journal.json backend/drizzle/0002_add_index.sql drizzle.config.ts \
         backend/drizzle.config.json src/database/drizzle.module.ts src/database/seeds/orders.ts \
         src/modules/orders/schema/orders.ts backend/src/modules/orders/schema/index.ts src/schema/shared.ts; do
  check T-F6 database allow "$r"; done
for r in src/modules/orders/orders.service.ts src/modules/orders/dto/create.dto.ts src/main.ts src/app.module.ts \
         package.json a/b/drizzle/x.sql drizzle src/database docs/contracts/orders.md docs/adr/014-x.md \
         .claude/hooks/x.sh .github/workflows/ci.yml lib/features/orders/data/orders_repository.dart .env; do
  check T-F6 database block "$r"; done
run_hook database "$tmp/src/modules/orders/orders.service.ts"
case "$err" in
  *"This agent (database) may not edit src/modules/orders/orders.service.ts. Report what needs to change instead."*) ok "T-F6 database blocked message" ;;
  *) bad "T-F6 database blocked message wrong: $err" ;;
esac

# ---- T-F7: path-fence regression. Each case checks the exit code AND the message.
# fcheck <id> <profile> <allow|block> <absolute file path> <root> [message substring, required for block]
# The message may list alternatives separated by " || ". An allow must print nothing.
fcheck() {
  local id="$1" profile="$2" want="$3" file="$4" proj="$5" msg="${6:-}" wantrc rest alt hit=0
  [ "$want" = allow ] && wantrc=0 || wantrc=2
  rc=0
  err="$(jq -n --arg f "$file" --arg c "$proj" '{tool_name:"Write",tool_input:{file_path:$f},cwd:$c}' \
    | CLAUDE_PROJECT_DIR="$proj" "$FENCE_BASH" "$hook" "$profile" 2>&1 >/dev/null)" || rc=$?
  if [ "$rc" -ne "$wantrc" ]; then bad "$id $profile expected $want ($wantrc) got exit $rc for $file: $err"; return; fi
  if [ "$want" = allow ]; then
    if [ -z "$err" ]; then ok "$id $profile allow $file"; else bad "$id $profile allowed but printed: $err"; fi
    return
  fi
  if [ -z "$msg" ]; then bad "$id (test bug: a block assertion needs a message substring)"; return; fi
  rest="$msg"
  while :; do
    case "$rest" in *" || "*) alt="${rest%% || *}"; rest="${rest#* || }" ;; *) alt="$rest"; rest="" ;; esac
    case "$err" in *"$alt"*) hit=1 ;; esac
    [ -n "$rest" ] || break
  done
  if [ "$hit" = 1 ]; then ok "$id $profile block $file"; else bad "$id $profile exit 2 but message lacks '$msg' for $file: $err"; fi
}
S="$(printf '\305\277')"; K="$(printf '\342\204\252')"; E="$(printf '\303\251')"
mkdir -p "$tmp/docs/design" "$tmp/perf" "$tmp/drizzle"

# T-F7a (repeated slashes): blocked in every profile, whatever the path would otherwise be. Canonical controls allow.
for pair in 'architecture|docs/contracts/x.md' 'tests|test/a_test.dart' 'devops|.github/workflows/ci.yml' 'design|docs/design/t.md' \
            'perf|perf/b.json' 'database|drizzle/0001_init.sql'; do
  profile="${pair%%|*}"; rel="${pair#*|}"
  fcheck T-F7a "$profile" allow "$tmp/$rel" "$tmp"
  fcheck T-F7a "$profile" block "$tmp//$rel" "$tmp" "repeated slashes"
  fcheck T-F7a "$profile" block "$tmp/${rel%%/*}//${rel#*/}" "$tmp" "repeated slashes"
  fcheck T-F7a "$profile" block "/$tmp/$rel" "$tmp" "repeated slashes"
  fcheck T-F7a "$profile" block "$tmp///$rel" "$tmp" "repeated slashes"
done
# A root with a repeated slash of its own is normalised on both sides.
fcheck T-F7a design block "$tmp//docs/design/t.md" "$tmp/" "repeated slashes"
fcheck T-F7a design allow "$tmp/docs/design/t.md" "$tmp/"

# T-F7b (root under a tests/ folder): the tests profile is unanchored, so an absolute rel would match the root's own tests/.
# A path that is not under the root by its plain spelling must not be allowed by that accident.
R="$tmp/tests/proj"
fcheck T-F7b tests allow "$R/test/a_test.dart" "$R"
fcheck T-F7b tests allow "$R/e2e/checkout.spec.ts" "$R"
fcheck T-F7b tests allow "$R/tests/b.ts" "$R"
fcheck T-F7b tests block "$R/lib/main.dart" "$R" "This agent (tests) may not edit lib/main.dart"
fcheck T-F7b tests block "$R/src/features/a.ts" "$R" "This agent (tests) may not edit src/features/a.ts"
fcheck T-F7b tests block "$R/.claude/hooks/x.sh" "$R" "This agent (tests) may not edit .claude/hooks/x.sh"
fcheck T-F7b tests block "$R//lib/main.dart" "$R" "repeated slashes"
fcheck T-F7b tests block "$R/lib//main.dart" "$R" "repeated slashes"
fcheck T-F7b tests block "$tmp/tests//proj/lib/main.dart" "$R" "repeated slashes"
fcheck T-F7b tests block "/$R/lib/main.dart" "$R" "repeated slashes"
fcheck T-F7b tests block "$R/test/../lib/main.dart" "$R" "without . or .. segments"
fcheck T-F7b tests block "$R/lib/./main.dart" "$R" "without . or .. segments"
# Folded spellings of the root. The file system may read U+017F as s and U+212A as k, so the write can land in the root.
RK="$tmp/tests/pk"; RS="$tmp/tests/ps"
fcheck T-F7b tests allow "$RK/test/a_test.dart" "$RK"
fcheck T-F7b tests block "$tmp/tests/p${K}/lib/main.dart" "$RK" "printable ASCII"
fcheck T-F7b tests block "$tmp/tests/p${S}/lib/main.dart" "$RS" "printable ASCII"
fcheck T-F7b tests block "$tmp/te${S}ts/pk/lib/main.dart" "$RK" "printable ASCII"
fcheck T-F7b tests block "$tmp/tests/p${K}/test/a_test.dart" "$RK" "printable ASCII"
# The other profiles are anchored at the root, so a root under tests/ changes nothing for them.
fcheck T-F7b architecture allow "$R/docs/contracts/x.md" "$R"
fcheck T-F7b architecture block "$R/lib/x.dart" "$R" "This agent (architecture) may not edit lib/x.dart"
fcheck T-F7b devops allow "$R/.github/workflows/ci.yml" "$R"
fcheck T-F7b devops block "$R/src/main.ts" "$R" "This agent (devops) may not edit src/main.ts"
fcheck T-F7b perf block "$R/lib/main.dart" "$R" "This agent (perf) may not edit lib/main.dart"
fcheck T-F7b database block "$R/src/main.ts" "$R" "This agent (database) may not edit src/main.ts"

# T-F7c (folding and non-ASCII under the root): only printable ASCII names are allowed in any profile.
for pair in "architecture|docs/contracts/${S}.md" "architecture|docs/contracts/caf${E}.md" "architecture|doc${S}/contracts/x.md" \
            "tests|test/${S}_test.dart" "tests|te${S}t/a_test.dart" "tests|test/a${K}_test.dart" "tests|e2e/caf${E}.spec.ts" \
            "devops|.github/wor${K}flows/ci.yml" "devops|scripts/${S}.sh" "devops|.github/workflows/ci${E}.yml" \
            "design|docs/de${S}ign/t.md" "design|docs/design/${K}.md" "design|docs/design/caf${E}.md" \
            "perf|perf/${S}.json" "perf|per${K}/b.json" "perf|perf/b${E}.json" \
            "database|drizzle/${K}.sql" "database|drizzle/0001_${S}.sql" "database|drizzle/caf${E}.sql"; do
  profile="${pair%%|*}"; rel="${pair#*|}"
  fcheck T-F7c "$profile" block "$tmp/$rel" "$tmp" "printable ASCII"
done
# Outside the root the whole path counts: a non-ASCII or repeated-slash path never reaches an allow.
fcheck T-F7c tests block "$tmp/../${S}/test/a_test.dart" "$tmp" "without . or .. segments || printable ASCII"
fcheck T-F7c architecture block "/outside/${K}/docs/contracts/x.md" "$tmp" "printable ASCII || may not edit"

# T-F7d (canonical in-role paths): exit 0 and no output; and the canonical out-of-role paths: exit 2 and the standard message.
while IFS='|' read -r profile want rel; do
  [ -n "$profile" ] || continue
  if [ "$want" = allow ]; then fcheck T-F7d "$profile" allow "$tmp/$rel" "$tmp"
  else fcheck T-F7d "$profile" block "$tmp/$rel" "$tmp" "This agent ($profile) may not edit $rel. Report what needs to change instead."; fi
done <<'ROWS'
architecture|allow|docs/contracts/orders.md
architecture|allow|docs/adr/012-x.md
architecture|block|docs/design/tokens.md
architecture|block|docs/contracts
architecture|block|lib/features/orders/a.dart
architecture|block|README.md
tests|allow|test/a_test.dart
tests|allow|tests/b.ts
tests|allow|integration_test/app_test.dart
tests|allow|e2e/checkout.spec.ts
tests|allow|fixtures/orders.json
tests|allow|lib/features/orders/orders_test.dart
tests|allow|src/orders/orders.spec.ts
tests|allow|src/orders/orders.test.tsx
tests|allow|test/orders.e2e-spec.ts
tests|allow|web/e2e/a.ts
tests|block|lib/main.dart
tests|block|src/main.ts
tests|block|package.json
tests|block|.claude/hooks/x.sh
tests|block|docs/contracts/orders.md
devops|allow|.github/workflows/ci.yml
devops|allow|infra/main.tf
devops|allow|deploy/a.yml
devops|allow|k8s/x.yaml
devops|allow|fastlane/Fastfile
devops|allow|scripts/x.sh
devops|allow|docs/ops.md
devops|allow|docs/runbooks/r.md
devops|allow|.env.example
devops|allow|.nvmrc
devops|allow|.dockerignore
devops|allow|Dockerfile
devops|allow|backend/Dockerfile.prod
devops|allow|docker-compose.yml
devops|block|src/main.ts
devops|block|lib/main.dart
devops|block|.env
devops|block|docs/contracts/orders.md
design|allow|docs/contracts/orders.md
design|allow|docs/design/tokens.md
design|allow|docs/design/orders/flow.md
design|block|docs/adr/012-x.md
design|block|src/features/orders/ui/a.tsx
perf|allow|perf/budgets.json
perf|allow|web/perf/checkout.ts
perf|allow|load/orders.js
perf|allow|integration_test/startup_perf_test.dart
perf|allow|.size-limit.json
perf|allow|lighthouserc.json
perf|block|e2e/checkout.spec.ts
perf|block|lib/main.dart
perf|block|package.json
database|allow|drizzle/0001_init.sql
database|allow|drizzle.config.ts
database|allow|src/database/drizzle.module.ts
database|allow|src/modules/orders/schema/orders.ts
database|allow|backend/drizzle/0002_x.sql
database|block|src/modules/orders/orders.service.ts
database|block|src/main.ts
database|block|.env
database|block|docs/contracts/orders.md
ROWS
# Dot segments in every profile name the rule.
for pair in 'architecture|docs/contracts/../../lib/x.dart' 'tests|test/../lib/main.dart' 'devops|scripts/../src/main.ts' 'design|docs/design/../../lib/x.dart' \
            'perf|perf/../lib/main.dart' 'database|drizzle/../../.claude/hooks/x.sh' 'perf|perf/./b.json'; do
  fcheck T-F7d "${pair%%|*}" block "$tmp/${pair#*|}" "$tmp" "without . or .. segments"
done

# T-F7e (known gaps, reported and not failed): input the fence ignores. contract-gate.sh is the layer that fails closed on these.
run_raw() { # run_raw <profile> <stdin text>
  rc=0; err="$(printf '%s' "$2" | CLAUDE_PROJECT_DIR="$tmp" "$FENCE_BASH" "$hook" "$1" 2>&1 >/dev/null)" || rc=$?
}
run_raw perf '{bad'
if [ "$rc" -eq 2 ]; then ok "T-F7e malformed JSON blocks"; else known "T-F7e malformed JSON exits $rc (allowed); contract-gate.sh fails closed on it"; fi
run_raw perf '{"tool_name":"Write","tool_input":{"file_path":5}}'
if [ "$rc" -eq 2 ]; then ok "T-F7e non-string file_path blocks"; else known "T-F7e non-string file_path exits $rc (allowed); contract-gate.sh fails closed on it"; fi
# A root that itself contains a repeated slash: the canonical write is outside it by spelling, and a write spelled
# with the same // is a repeated-slash path. Both fail closed; contract-gate.sh collapses the root instead.
rc=0
err="$(jq -n --arg f "$tmp/sub/docs/design/t.md" '{tool_name:"Write",tool_input:{file_path:$f}}' \
  | CLAUDE_PROJECT_DIR="$tmp//sub" "$FENCE_BASH" "$hook" design 2>&1 >/dev/null)" || rc=$?
if [ "$rc" -eq 0 ]; then ok "T-F7e design, root with its own //, canonical in-role write allowed"
else known "T-F7e design, root spelled with // (CLAUDE_PROJECT_DIR=\$tmp//sub): the in-role write $tmp/sub/docs/design/t.md exits $rc (blocked, fail closed)"; fi
# A root under tests/ reached through a symlinked parent: the alias is not resolved, so the unanchored tests rule can match.
mkdir -p "$tmp/real/tests/proj" && ln -s "$tmp/real" "$tmp/aliasreal"
rc=0
err="$(jq -n --arg f "$tmp/aliasreal/tests/proj/lib/main.dart" '{tool_name:"Write",tool_input:{file_path:$f}}' \
  | CLAUDE_PROJECT_DIR="$tmp/real/tests/proj" "$FENCE_BASH" "$hook" tests 2>&1 >/dev/null)" || rc=$?
if [ "$rc" -eq 2 ]; then ok "T-F7e tests profile, root under tests/ reached through a symlinked parent blocks"
else known "T-F7e tests profile, lib/main.dart reached through a symlink to a root under tests/ exits $rc (allowed): aliases are not resolved"; fi

# The hook only reads: the repo state must be unchanged
after="$(git_state)"
if [ "$before" = "$after" ]; then ok "repo git status --porcelain unchanged"; else bad "repo git status changed during the run"; fi

echo "Summary: $pass ok, $fail fail, $gap known gap"
[ "$fail" -eq 0 ]
