#!/usr/bin/env bash
# Regression tests for .claude/hooks/contract-gate.sh: the full suite for the patched hook.
# Covers: speed on a large contract (the hook is registered with timeout 10 and onFailure block),
# the approval and reopen rules, exact old_string matching, gate paths, symlinks, aliases, hard
# links and file system folding, NUL and control characters, bad input, jq failures, the
# no-weakening comparison against a frozen copy of the pre-patch hook, and the finding ids
# named in each test (A to G: folding, NUL, NotebookEdit decoy, re-run, bad input, single-letter
# root, partial apply).
# Usage: contract-gate-test.sh
#   GATE       hook under test (default .claude/hooks/contract-gate.sh, relative to the repo root)
#   GATE_BASH  shell that runs it (default /bin/bash, macOS bash 3.2)
#   JQ         jq binary put first on PATH for the hook and for this script (default: the jq on PATH)
#   ALLOW_SKIP=1     the run does not fail on a skipped case (the skip list is still printed)
#   BASELINE_GATE    hook used as the no-weakening baseline (default: the frozen pre-patch copy in
#                    scripts/tests/fixtures/, checked against BASELINE_SHA256 and copied to the temp dir)
#   BIG_KB     size of the large-contract timing fixture in T-G40 (default 500)
#   MATRIX     when set, a file that gets one line per case: id, baseline exit, exit under test
#   REPO_ROOT  repo whose git state must stay unchanged (default: two folders above this script)
# A skipped case fails the run unless ALLOW_SKIP=1. Every block assertion checks a message.
# Builds every fixture in a mktemp root. Never modifies the repo. Needs bash, jq, awk, sed, kill.
# Every run of the hook is under a watchdog that kills it, so a slow hook fails fast and never hangs.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${REPO_ROOT:-$(cd "$here/../.." && pwd)}"
GATE="${GATE:-.claude/hooks/contract-gate.sh}"
GATE_BASH="${GATE_BASH:-/bin/bash}"
case "$GATE" in /*) ;; *) GATE="$root/$GATE" ;; esac
# The pre-patch hook, frozen: sha256 of scripts/tests/fixtures/contract-gate.pre-patch.sh.
BASELINE_SHA256="e46fec1a7f09d099328da5d0183528daa984e67848cd7c2d706c72ab9ef54055"

# TMPDIR may end in a slash (macOS does), which would put a // in every fixture path.
tbase="${TMPDIR:-/tmp}"; tbase="${tbase%/}"
tmp="$(mktemp -d "$tbase/contract-gate-test.XXXXXX")"
case "$tmp" in
  "$tbase"/contract-gate-test.*) ;;
  *) echo "FAIL: unsafe temp dir '$tmp'"; exit 1 ;;
esac
trap 'rm -rf "$tmp" "$(dirname "$tmp")/cgt-alias.$$"' EXIT

if [ -n "${JQ:-}" ]; then
  [ -x "$JQ" ] || { echo "FAIL: JQ=$JQ is not executable"; exit 1; }
  mkdir -p "$tmp/jqbin"; ln -s "$JQ" "$tmp/jqbin/jq"; PATH="$tmp/jqbin:$PATH"; export PATH
fi
command -v jq >/dev/null || { echo "FAIL: jq is required"; exit 1; }
command -v awk >/dev/null || { echo "FAIL: awk is required"; exit 1; }
[ -f "$GATE" ] || { echo "FAIL: $GATE not found"; exit 1; }
[ -x "$GATE_BASH" ] || command -v "$GATE_BASH" >/dev/null || { echo "FAIL: $GATE_BASH not found"; exit 1; }

# sha256 of a file or stdin, with whichever tool exists (macOS shasum, Linux sha256sum).
sha() {
  if command -v shasum >/dev/null; then shasum -a 256 "$@" | awk '{print $1}'
  elif command -v sha256sum >/dev/null; then sha256sum "$@" | awk '{print $1}'
  else cksum "$@" | awk '{print $1}'; fi
}

# The no-weakening baseline: a frozen copy of the pre-patch hook, never the live hook. It is copied
# into the temp dir and its hash is checked, so an edit to the fixture or to the live hook cannot change it.
if [ -z "${BASELINE_GATE:-}" ]; then
  [ -f "$here/fixtures/contract-gate.pre-patch.sh" ] || { echo "FAIL: $here/fixtures/contract-gate.pre-patch.sh not found"; exit 1; }
  cp "$here/fixtures/contract-gate.pre-patch.sh" "$tmp/baseline-gate.sh"
  [ "$(sha "$tmp/baseline-gate.sh")" = "$BASELINE_SHA256" ] || { echo "FAIL: the frozen baseline hook does not match BASELINE_SHA256"; exit 1; }
  BASELINE_GATE="$tmp/baseline-gate.sh"
fi
[ -f "$BASELINE_GATE" ] || { echo "FAIL: baseline $BASELINE_GATE not found"; exit 1; }
CURRENT_GATE="$BASELINE_GATE"

pass=0; fail=0; gap=0; skipped=0; skiplist=""
skip() { echo "SKIP: $1"; skipped=$((skipped + 1)); skiplist="$skiplist
  - $1"; }
ok()   { echo "OK: $1"; pass=$((pass + 1)); }
bad()  { echo "FAIL: $1"; fail=$((fail + 1)); }
known() { echo "KNOWN GAP: $1"; gap=$((gap + 1)); }

# Fingerprint of the working tree: status, tracked diff (unstaged and staged), and the content of every
# untracked file. Catches writes to files that were already modified or untracked, which status alone misses.
git_state() {
  {
    git -C "$root" status --porcelain 2>/dev/null || true
    git -C "$root" diff 2>/dev/null || true
    git -C "$root" diff --cached 2>/dev/null || true
    git -C "$root" ls-files -o --exclude-standard -z 2>/dev/null | while IFS= read -r -d '' f; do
      sha "$root/$f" 2>/dev/null || true
    done
  } | sha
}
before="$(git_state)"

echo "gate: $GATE"
echo "baseline (frozen pre-patch hook): $BASELINE_GATE sha256 $(sha "$BASELINE_GATE")"
echo "shell: $GATE_BASH ($("$GATE_BASH" --version | head -n 1))"
echo "jq: $(command -v jq) ($(jq --version))"

proj="$tmp/proj"
mkdir -p "$proj/docs/contracts"

# put_contract <name> <status> : a small contract with a frontmatter status and a body
put_contract() {
  printf -- '---\nstatus: %s\nowner: dave\n---\n# %s\nBody line one.\nBody line two.\n' "$2" "$1" > "$proj/docs/contracts/$1.md"
}

# Large contract: 1,300 lines, draft, with a unique marker and a token that repeats.
big="$proj/docs/contracts/big.md"
{
  printf -- '---\nstatus: draft\nowner: dave\n---\n# Big contract\n'
  awk 'BEGIN { for (i = 1; i <= 1300; i++) {
         printf "Line %d: the agent reads the contract, checks the invariant, and reports the exact command and result.\n", i
         if (i % 100 == 0) printf "repeat-token appears here (%d)\n", i
         if (i == 900) printf "UNIQUE-MARKER-LINE to edit\n"
       } }'
} > "$big"
big_lines="$(wc -l < "$big" | tr -d ' ')"
[ "$big_lines" -ge 1200 ] || { echo "FAIL: fixture has only $big_lines lines"; exit 1; }

# The real large contract, when present, is the reported reproduction.
real="$root/docs/contracts/kit-extra-agents.md"
if [ -f "$real" ]; then cp "$real" "$proj/docs/contracts/kit-extra-agents.md"; fi

# run_gate <limit_seconds> <json_file> -> sets rc, err, hung (1 when the watchdog killed it), ticks (100 ms units)
run_gate() {
  local limit="$1" jf="$2" pid max i=0
  hung=0; rc=0
  : > "$tmp/err"
  crc=-
  if [ -n "${MATRIX:-}" ]; then
    # Baseline run under its own watchdog (MATRIX_LIMIT seconds, default 20). The current hook
    # takes minutes on a large contract; a killed baseline is recorded as "timeout".
    local bpid j=0
    crc=0
    PATH="${gate_path:-$PATH}" CLAUDE_PROJECT_DIR="${gate_root-$proj}" "$GATE_BASH" "$CURRENT_GATE" < "$jf" > /dev/null 2>&1 &
    bpid=$!
    while kill -0 "$bpid" 2>/dev/null; do
      if [ "$j" -ge $(( ${MATRIX_LIMIT:-20} * 10 )) ]; then
        pkill -9 -P "$bpid" 2>/dev/null || true; kill -9 "$bpid" 2>/dev/null || true; crc=timeout; break
      fi
      sleep 0.1; j=$((j + 1))
    done
    if [ "$crc" = timeout ]; then { wait "$bpid"; } 2>/dev/null || true
    else { wait "$bpid"; } 2>/dev/null || crc=$?; fi
  fi
  PATH="${gate_path:-$PATH}" CLAUDE_PROJECT_DIR="${gate_root-$proj}" "$GATE_BASH" "$GATE" < "$jf" > "$tmp/out" 2> "$tmp/err" &
  pid=$!
  max=$((limit * 10))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$i" -ge "$max" ]; then
      hung=1
      pkill -9 -P "$pid" 2>/dev/null || true
      kill -9 "$pid" 2>/dev/null || true
      break
    fi
    sleep 0.1
    i=$((i + 1))
  done
  { wait "$pid"; } 2>/dev/null || rc=$?
  ticks=$i
  err="$(cat "$tmp/err" 2>/dev/null || true)"
}

# mk_edit <rel> <old> <new> [replace_all]  -> json file
mk_edit() {
  jq -n --arg f "$proj/$1" --arg o "$2" --arg n "$3" --argjson ra "${4:-false}" \
    '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n,replace_all:$ra},cwd:"/nowhere"}' > "$tmp/in.json"
}
# mk_write <rel> <content-file> -> json file
mk_write() {
  jq -n --arg f "$proj/$1" --rawfile c "$2" \
    '{tool_name:"Write",tool_input:{file_path:$f,content:$c},cwd:"/nowhere"}' > "$tmp/in.json"
}
mk_write_str() {
  printf '%s' "$2" > "$tmp/content.txt"
  mk_write "$1" "$tmp/content.txt"
}

# expect <id> <allow|block> <message-substring>  (uses rc, err, hung from the last run_gate)
expect() {
  local id="$1" want="$2" msg="${3:-}" wantrc
  [ -z "${MATRIX:-}" ] || printf '%s\t%s\t%s\n' "$id" "$crc" "$rc" >> "$MATRIX"
  [ "$want" = allow ] && wantrc=0 || wantrc=2
  if [ "$hung" -eq 1 ]; then bad "$id hung, killed by the watchdog"; return; fi
  if [ "$rc" -ne "$wantrc" ]; then bad "$id expected $want ($wantrc) got exit $rc: $err"; return; fi
  # Every block must name its reason. msg may list alternatives separated by " || ".
  if [ "$want" = block ] && [ -z "$msg" ]; then bad "$id (test bug: a block assertion needs a message substring)"; return; fi
  if [ -n "$msg" ]; then
    local rest="$msg" alt hit=0
    while :; do
      case "$rest" in *" || "*) alt="${rest%% || *}"; rest="${rest#* || }" ;; *) alt="$rest"; rest="" ;; esac
      case "$err" in *"$alt"*) hit=1 ;; esac
      [ -n "$rest" ] || break
    done
    if [ "$hit" = 1 ]; then ok "$id $want"; else bad "$id exit $rc but message lacks '$msg': $err"; fi
  else ok "$id $want"; fi
}

# timed <id> <limit_seconds> : fails when the watchdog fired or the run exceeded the limit
timed() {
  local id="$1" limit="$2"
  if [ "$hung" -eq 1 ]; then bad "$id still running after ${limit}s, killed by the watchdog (hook timeout is 10s)"
  elif [ "$ticks" -gt $((limit * 10)) ]; then bad "$id took ~$((ticks * 100)) ms, over ${limit}s"
  else ok "$id finished in ~$((ticks * 100)) ms (limit ${limit}s)"; fi
}

# ---- Timing on a large contract: Edit, Edit with replace_all, Write, each within 2 seconds
echo "# timing ($big_lines-line contract)"
# old_string starts with a common letter, like real edits. A rare first character hides the slowness.
mk_edit docs/contracts/big.md "Line 900: the agent reads the contract, checks the invariant, and reports the exact command and result." "Line 900: reworded."
run_gate 2 "$tmp/in.json"; timed "T-G1 Edit on large contract" 2
if [ "$hung" -eq 0 ]; then expect "T-G1 Edit on large contract result" allow; fi

mk_edit docs/contracts/big.md "repeat-token" "repeat-word" true
run_gate 2 "$tmp/in.json"; timed "T-G2 Edit replace_all on large contract" 2
if [ "$hung" -eq 0 ]; then expect "T-G2 Edit replace_all on large contract result" allow; fi

mk_write docs/contracts/big.md "$big"
run_gate 2 "$tmp/in.json"; timed "T-G3 Write on large contract" 2
if [ "$hung" -eq 0 ]; then expect "T-G3 Write on large contract result" allow; fi

if [ -f "$proj/docs/contracts/kit-extra-agents.md" ]; then
  mk_edit docs/contracts/kit-extra-agents.md "## Tests" "## Tests (edited)"
  run_gate 2 "$tmp/in.json"; timed "T-G4 Edit on real kit-extra-agents.md ($(wc -l < "$real" | tr -d ' ') lines)" 2
fi

# Behavior cases use small fixtures; the 5s watchdog only protects the total run time.
lim=5

# ---- Gate paths are blocked
echo "# gate paths"
for r in .claude/hooks/x.sh .claude/settings.json scripts/check-contracts.sh .github/workflows/agent-gates.yml; do
  mk_write_str "$r" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G5 gate path $r" block "is a gate"
done

# ---- Draft to approved
echo "# approval"
put_contract draftc draft
mk_edit docs/contracts/draftc.md "status: draft" "status: approved"
run_gate $lim "$tmp/in.json"; expect "T-G6 draft to approved via Edit" block "Only Dave approves"

mk_write_str docs/contracts/draftc.md "$(printf -- '---\nstatus: approved\n---\n# draftc\n')"
run_gate $lim "$tmp/in.json"; expect "T-G7 draft to approved via Write" block "Only Dave approves"

mk_write_str docs/contracts/brandnew.md "$(printf -- '---\nstatus: approved\n---\n# new\n')"
run_gate $lim "$tmp/in.json"; expect "T-G7b new file written as approved" block "Only Dave approves"

# First status line decides: an approved line further down must not count, and does not flip the gate.
printf -- '---\nstatus: draft\n---\n# firstline\nExample block:\nstatus: pending-example\nend\n' > "$proj/docs/contracts/firstline.md"
mk_edit docs/contracts/firstline.md "status: pending-example" "status: approved"
run_gate $lim "$tmp/in.json"; expect "T-G8 status: approved only below the first status line is decided by the first line" allow

# Approved contracts reopen before they change.
put_contract apprc approved
mk_edit docs/contracts/apprc.md "Body line one." "Body line one, changed."
run_gate $lim "$tmp/in.json"; expect "T-G9 approved contract body edit without draft" block "is approved. Set status: draft"

mk_edit docs/contracts/apprc.md "status: approved" "status: approved"
run_gate $lim "$tmp/in.json"; expect "T-G9b approved contract edit that keeps approved" block "is approved. Set status: draft"

mk_edit docs/contracts/apprc.md "status: approved" "status: draft"
run_gate $lim "$tmp/in.json"; expect "T-G10 approved contract edit that sets draft" allow

mk_write_str docs/contracts/apprc.md "$(printf -- '---\nstatus: draft\n---\n# apprc\nrewritten\n')"
run_gate $lim "$tmp/in.json"; expect "T-G10b approved contract Write that sets draft" allow

mk_write_str docs/contracts/apprc.md "$(printf -- '---\nstatus: approved\n---\n# apprc\nrewritten\n')"
run_gate $lim "$tmp/in.json"; expect "T-G10c approved contract Write that stays approved" block "is approved. Set status: draft"

# Draft contract body edit
mk_edit docs/contracts/draftc.md "Body line two." "Body line two, changed."
run_gate $lim "$tmp/in.json"; expect "T-G11 draft contract body edit" allow

# ---- Case sensitivity: Claude Code's Edit matches old_string literally and case-sensitively.
echo "# case sensitivity"
# (a) The Edit matches nothing, so the file is unchanged and stays draft. A case-insensitive replace
#     would turn it into status: approved and wrongly block.
put_contract casea draft
mk_edit docs/contracts/casea.md "STATUS: DRAFT" "status: approved"
run_gate $lim "$tmp/in.json"; expect "T-G12 case: old_string differs only in case, no exact match, blocks" block "must match docs/contracts/casea.md exactly"

# (b) A harmless earlier line differs only in case. The literal Edit flips the real frontmatter line to
#     approved, so the gate must block. A case-insensitive replace hits the earlier line instead and
#     lets an approval through.
printf -- '---\ntitle: STATUS: DRAFT tracker\nstatus: draft\n---\n# caseb\n' > "$proj/docs/contracts/caseb.md"
mk_edit docs/contracts/caseb.md "status: draft" "status: approved"
run_gate $lim "$tmp/in.json"; expect "T-G13 case: earlier case-variant text must not hide a real draft to approved edit" block "Only Dave approves"

# (c) Same idea with an already approved file: the literal edit sets draft, so it passes.
printf -- '---\nnote: STATUS: APPROVED tracker\nstatus: approved\n---\n# casec\n' > "$proj/docs/contracts/casec.md"
mk_edit docs/contracts/casec.md "status: approved" "status: draft"
run_gate $lim "$tmp/in.json"; expect "T-G14 case: approved to draft edit passes when an earlier case-variant line exists" allow

# (d) Capitalised value: status_of reads lower-case letters, so the literal edit to approved is blocked.
printf -- '---\nstatus: Draft\n---\n# cased\n' > "$proj/docs/contracts/cased.md"
mk_edit docs/contracts/cased.md "status: Draft" "status: approved"
run_gate $lim "$tmp/in.json"; expect "T-G15 case: status: Draft to status: approved via literal match" block "Only Dave approves"

# (e) old_string differs in case from a Draft value: literal replace matches nothing, file stays unchanged.
mk_edit docs/contracts/cased.md "status: draft" "status: approved"
run_gate $lim "$tmp/in.json"; expect "T-G16 case: status: draft does not literally match status: Draft, blocks" block "must match docs/contracts/cased.md exactly"

# ---- Feature code
echo "# feature code"
mk_write_str src/features/nocontract/a.ts "x"
run_gate $lim "$tmp/in.json"; expect "T-G17 feature code, no contract and no folder" block "has no contract"

put_contract draftf draft
mk_write_str src/features/draftf/a.ts "x"
run_gate $lim "$tmp/in.json"; expect "T-G18 feature code, draft contract" block "is not approved yet"

put_contract apprf approved
mk_write_str src/features/apprf/a.ts "x"
run_gate $lim "$tmp/in.json"; expect "T-G19 feature code, approved contract" allow

# ---- Dot segments
echo "# dot segments"
for r in "docs/../.claude/hooks/x.sh" "src/features/apprf/../../../.claude/settings.json" "docs/./contracts/draftc.md"; do
  mk_write_str "$r" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G20 dot segments in $r" block "without . or .. segments"
done

# ---- T-G21: Edit with an empty old_string creates a new file whose content is new_string.
echo "# edit creates a file"
rm -f "$proj/docs/contracts/created.md"
mk_edit docs/contracts/created.md "" "$(printf -- '---\nstatus: approved\n---\n# created\n')"
run_gate $lim "$tmp/in.json"; expect "T-G21a Edit creates a missing contract as approved" block "Only Dave approves a contract"

rm -f "$proj/docs/contracts/created.md"
mk_edit docs/contracts/created.md "" "$(printf -- '---\nstatus: draft\n---\n# created\n')"
run_gate $lim "$tmp/in.json"; expect "T-G21b Edit creates a missing contract as draft" allow

put_contract createdexisting approved
mk_edit docs/contracts/createdexisting.md "" "$(printf -- '---\nowner: dave\n---\n# no status line\n')"
run_gate $lim "$tmp/in.json"; expect "T-G21c Edit with empty old_string on an approved contract, no status: draft" block "is approved. Set status: draft"

# ---- T-G29 (F2): empty old_string on a file with content blocks. Missing or empty files are created.
echo "# empty old_string on an existing file"
put_contract eapp approved
mk_edit docs/contracts/eapp.md "" "$(printf -- '---\nstatus: draft\n---\n# eapp\n')"
run_gate $lim "$tmp/in.json"; expect "T-G29a empty old_string on approved, new_string sets draft" block "empty old_string on existing docs/contracts/eapp.md"
run_gate $lim "$tmp/in.json"; expect "T-G29a2 same, message keeps the reopen hint" block "is approved. Set status: draft"
put_contract edraft draft
mk_edit docs/contracts/edraft.md "" "$(printf -- '---\nstatus: draft\n---\n# edraft\n')"
run_gate $lim "$tmp/in.json"; expect "T-G29b empty old_string on draft" block "empty old_string on existing docs/contracts/edraft.md"
: > "$proj/docs/contracts/eempty.md"
mk_edit docs/contracts/eempty.md "" "$(printf -- '---\nstatus: draft\n---\n# eempty\n')"
run_gate $lim "$tmp/in.json"; expect "T-G29c empty old_string on an empty file, draft" allow
mk_edit docs/contracts/eempty.md "" "$(printf -- '---\nstatus: approved\n---\n# eempty\n')"
run_gate $lim "$tmp/in.json"; expect "T-G29d empty old_string on an empty file, approved" block "Only Dave approves"
rm -f "$proj/docs/contracts/emissing.md"
mk_edit docs/contracts/emissing.md "" "$(printf -- '---\nstatus: draft\n---\n# emissing\n')"
run_gate $lim "$tmp/in.json"; expect "T-G29e empty old_string on a missing file, draft" allow
mk_edit docs/contracts/emissing.md "" "$(printf -- '---\nstatus: approved\n---\n# emissing\n')"
run_gate $lim "$tmp/in.json"; expect "T-G29f empty old_string on a missing file, approved" block "Only Dave approves"

# ---- T-G30 (F3): only Edit and Write are modeled on a contract. Any other tool blocks.
echo "# other tools on a contract"
put_contract tools draft
for t in MultiEdit NotebookEdit edit ""; do
  # NotebookEdit writes notebook_path (revision 3 requires it), so it gets both fields here.
  jq -n --arg t "$t" --arg f "$proj/docs/contracts/tools.md" \
    '{tool_name:$t,tool_input:({file_path:$f,old_string:"Body line one.",new_string:"Body",new_source:"status: approved"}
      + (if $t == "NotebookEdit" then {notebook_path:$f} else {} end)),cwd:"/nowhere"}' > "$tmp/in.json"
  run_gate $lim "$tmp/in.json"; expect "T-G30 tool_name '$t' on a contract" block "use Edit or Write on docs/contracts/tools.md"
done
jq -n --arg f "$proj/docs/contracts/tools.md" '{tool_input:{file_path:$f,content:"x"},cwd:"/nowhere"}' > "$tmp/in.json"
run_gate $lim "$tmp/in.json"; expect "T-G30 tool_name missing on a contract" block "not an unnamed tool"

# ---- T-G22: fail closed on casing. Only the exact lower-case 'status: approved' counts as approved.
echo "# approval casing fails closed"
n=0
for line in "Status: Approved" "status: Approved"; do
  n=$((n + 1)); f="casing$n"
  printf -- '---\n%s\n---\n# %s\n' "$line" "$f" > "$proj/docs/contracts/$f.md"
  mk_write_str "src/features/$f/a.ts" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G22 feature code, contract frontmatter '$line' is not approved" block "is not approved yet"
done

# ---- T-G23: replace_all passed as the JSON string "true" must still count as replace-all.
echo "# replace_all as a string"
printf -- '---\ntitle: draft work\nstatus: draft\n---\n# strra\n' > "$proj/docs/contracts/strra.md"
mk_edit docs/contracts/strra.md "draft" "approved" '"true"'
run_gate $lim "$tmp/in.json"; expect "T-G23 replace_all as string \"true\" turning draft into approved" block "Only Dave approves"

# ---- T-G24: when jq fails on the content path, the hook must block rather than guess.
echo "# jq failure fails closed"
real_jq="$(command -v jq)"
mkdir -p "$tmp/fakebin"
cat > "$tmp/fakebin/jq" <<FAKE
#!/bin/sh
for a in "\$@"; do [ "\$a" = "--rawfile" ] && exit 1; done
exec "$real_jq" "\$@"
FAKE
chmod +x "$tmp/fakebin/jq"
put_contract jqfail draft
mk_edit docs/contracts/jqfail.md "status: draft" "status: approved"
gate_path="$tmp/fakebin:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G24 jq fails on --rawfile, Edit on a draft contract" block "could not compute"
unset gate_path

# ---- T-G24b/c/d: the contract jq call fails or prints something other than a verdict word.
# Revision 3 has no separate 'length' or '.[i]' calls: one jq call (the only one with --rawfile)
# prints the verdict. Shims delegate to the real jq except for that call.
echo "# jq verdict call misbehaves"
shim() { # shim <name> <sh-case-body>: writes $tmp/<name>/jq
  mkdir -p "$tmp/$1"
  {
    echo '#!/bin/sh'
    echo "$2"
    echo "exec \"$real_jq\" \"\$@\""
  } > "$tmp/$1/jq"
  chmod +x "$tmp/$1/jq"
}
put_contract jqfail2 draft
mk_edit docs/contracts/jqfail2.md "status: draft" "status: approved"

shim fakelen 'for a in "$@"; do [ "$a" = --rawfile ] && { echo; exit 0; }; done'
gate_path="$tmp/fakelen:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G24b verdict call prints an empty line, Edit draft to approved" block "could not compute"

shim fakeidx 'for a in "$@"; do [ "$a" = --rawfile ] && { echo garbage; exit 0; }; done'
gate_path="$tmp/fakeidx:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G24c verdict call prints an unknown word, Edit draft to approved" block "could not compute"

shim fakezero 'for a in "$@"; do [ "$a" = --rawfile ] && { echo 0; exit 0; }; done'
gate_path="$tmp/fakezero:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G24d verdict call prints 0, Edit draft to approved" block "could not compute"
unset gate_path

# ---- T-G27: replace_all matrix. The candidate gate must be at least as strict as the current hook.
echo "# replace_all matrix (value, case, current exit, candidate exit)"
mk_ra() { # mk_ra <rel> <old> <new> <ra-json|missing>
  if [ "$4" = missing ]; then
    jq -n --arg f "$proj/$1" --arg o "$2" --arg n "$3" \
      '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n},cwd:"/nowhere"}' > "$tmp/in.json"
  else
    jq -n --arg f "$proj/$1" --arg o "$2" --arg n "$3" --argjson ra "$4" \
      '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n,replace_all:$ra},cwd:"/nowhere"}' > "$tmp/in.json"
  fi
}
printf -- '---\ntitle: draft plan\nstatus: draft\n---\n# mxa\n' > "$proj/docs/contracts/mxa.md"
printf -- '---\ntitle: approved plan\nstatus: approved\n---\n# mxb\n' > "$proj/docs/contracts/mxb.md"
printf '%-8s %-5s %-8s %-9s\n' value case current candidate
for v in true false null missing '"true"' '"false"' 1 0; do
  for c in A B; do
    if [ "$c" = A ]; then mk_ra docs/contracts/mxa.md draft approved "$v"; else mk_ra docs/contracts/mxb.md approved draft "$v"; fi
    saved_gate="$GATE"
    GATE="$CURRENT_GATE"; run_gate 3 "$tmp/in.json"; base_rc=$rc; chung=$hung
    GATE="$saved_gate";   run_gate $lim "$tmp/in.json"; prc=$rc; phung=$hung
    crc=$base_rc; [ "$chung" -eq 1 ] && crc="hung"
    [ "$phung" -eq 1 ] && prc="hung"
    printf '%-8s %-5s %-8s %-9s\n' "$v" "$c" "$crc" "$prc"
    if [ "$phung" -eq 1 ]; then bad "T-G27 replace_all=$v case $c: candidate hung"
    elif [ "$crc" = 2 ] && [ "$prc" != 2 ]; then bad "T-G27 replace_all=$v case $c: current blocks (2) but candidate exits $prc"
    else ok "T-G27 replace_all=$v case $c: candidate at least as strict (current $crc, candidate $prc)"; fi
  done
done

# ---- T-G25: an unreadable contract cannot be compared, so the edit must block.
echo "# unreadable contract"
if [ "$(id -u)" -eq 0 ]; then
  skip "T-G25 unreadable contract (chmod 000 has no effect as root; run as a normal user). T-G25b still runs."
else
  put_contract unread draft
  chmod 000 "$proj/docs/contracts/unread.md"
  mk_edit docs/contracts/unread.md "status: draft" "status: approved"
  run_gate $lim "$tmp/in.json"; expect "T-G25 unreadable draft contract, Edit draft to approved" block "cannot read docs/contracts/unread.md"
  mk_edit docs/contracts/unread.md "status: draft" "status: draft2"
  run_gate $lim "$tmp/in.json"; expect "T-G25 unreadable draft contract, harmless Edit also blocks" block "cannot read docs/contracts/unread.md"
  chmod 600 "$proj/docs/contracts/unread.md"
  mk_edit docs/contracts/unread.md "status: draft" "status: draft2"
  run_gate $lim "$tmp/in.json"; expect "T-G25 control: the same contract readable again, harmless Edit" allow
fi
# T-G25b: a contract path that is a folder cannot be read either (works as root too).
mkdir -p "$proj/docs/contracts/adir.md"
mk_write_str docs/contracts/adir.md "$(printf -- '---\nstatus: draft\n---\n')"
run_gate $lim "$tmp/in.json"; expect "T-G25b contract path is a folder, Write" block "cannot read docs/contracts/adir.md"

# ---- T-G26: invalid UTF-8 in a contract. An approval must not get through, and a harmless edit of a
# draft must not be refused for a wrong reason. Run under a UTF-8 locale (BSD tr stops on invalid
# bytes there) and under the C locale.
echo "# invalid UTF-8"
printf -- '---\ntitle: \377\376\nstatus: draft\n---\n# badutf\nBody\n' > "$proj/docs/contracts/badutf.md"
u8=""
locales="$(locale -a 2>/dev/null || true)"
for l in en_US.UTF-8 C.UTF-8 en_US.utf8 C.utf8; do
  case "
$locales
" in *"
$l
"*) u8="$l"; break ;; esac
done
if [ -z "$u8" ]; then skip "T-G26 no UTF-8 locale is installed (locale -a), so the UTF-8 half of T-G26 did not run"; fi
for loc in ${u8:+"$u8"} C; do
  export LC_ALL="$loc"
  mk_edit docs/contracts/badutf.md "status: draft" "status: approved"
  run_gate $lim "$tmp/in.json"; expect "T-G26 [$loc] invalid UTF-8 bytes before status line, Edit draft to approved" block "Only Dave approves"
  mk_edit docs/contracts/badutf.md "Body" "Body"
  run_gate $lim "$tmp/in.json"; expect "T-G26 [$loc] control: invalid UTF-8 in a draft contract, harmless Edit" allow
  mk_write_str docs/contracts/badutf.md "$(printf -- '---\nstatus: approved\n---\n')"
  run_gate $lim "$tmp/in.json"; expect "T-G26 [$loc] invalid UTF-8 in the current file, Write as approved" block "Only Dave approves"
done
unset LC_ALL

# ---- T-G28: old_string must match exactly. The Edit tool may normalize when it does not.
echo "# exact match and normalized variants"
printf -- '---\nstatus: draft\nowner: dave\n---\n# esc\n' > "$proj/docs/contracts/esc.md"
mk_edit docs/contracts/esc.md 'status: dr\u0061ft' 'status: \u0061pproved'
run_gate $lim "$tmp/in.json"; expect "T-G28a escaped old_string with no exact match" block "must match docs/contracts/esc.md exactly"
printf -- '---\ntitle: \342\200\234Plan\342\200\235\nstatus: draft\n---\n# q\n' > "$proj/docs/contracts/q.md"
mk_edit docs/contracts/q.md "$(printf 'title: "Plan"\nstatus: draft')" "$(printf 'title: "Plan"\nstatus: approved')"
run_gate $lim "$tmp/in.json"; expect "T-G28b straight quotes against curly quotes in the file" block "must match docs/contracts/q.md exactly"
rm -f "$proj/docs/contracts/nofile.md"
mk_edit docs/contracts/nofile.md "x" "y"
run_gate $lim "$tmp/in.json"; expect "T-G28c missing file with non-empty old_string" block "does not exist"
put_contract varc draft
for v in 'status: \u0061pproved' 'status: \x61pproved' 'status: “approved”' 'Status: Approved' '  status: approved' '"status": approved' 'st\u0061tus: approved'; do
  mk_edit docs/contracts/varc.md "status: draft" "$v"
  run_gate $lim "$tmp/in.json"; expect "T-G28d new_string variant '$v'" block "Only Dave approves"
done
mk_write_str docs/contracts/varc.md "$(printf -- '---\nstatus: \\u0061pproved\n---\n')"
run_gate $lim "$tmp/in.json"; expect "T-G28e Write with escaped approved" block "Only Dave approves"
mk_edit docs/contracts/varc.md "Body line one." 'Body with \u0061 and \ud83d text.'
run_gate $lim "$tmp/in.json"; expect "T-G28f draft body edit with escape-like text" allow
printf -- '---\nstatus: Approved\n---\n# capa\nBody.\n' > "$proj/docs/contracts/capa.md"
mk_edit docs/contracts/capa.md "Body." "Body2."
run_gate $lim "$tmp/in.json"; expect "T-G28g loosely approved file needs reopen" block "is approved. Set status: draft"
mk_edit docs/contracts/capa.md "status: Approved" "status: draft"
run_gate $lim "$tmp/in.json"; expect "T-G28h loosely approved file reopened to draft" allow
# Verdict guard on an allowed edit: only the exact word ok allows.
put_contract cnt draft
mk_edit docs/contracts/cnt.md "Body line one." "Body line one, changed."
run_gate $lim "$tmp/in.json"; expect "T-G28i0 control: the allowed edit itself" allow
shim fakenan 'for a in "$@"; do [ "$a" = --rawfile ] && { echo null; exit 0; }; done'
gate_path="$tmp/fakenan:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G28i verdict call prints null" block "could not compute"
shim fakeempty 'for a in "$@"; do [ "$a" = --rawfile ] && exit 0; done'
gate_path="$tmp/fakeempty:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G28j verdict call prints nothing" block "could not compute"
shim fakezero2 'for a in "$@"; do [ "$a" = --rawfile ] && { printf 'ok\nok\n'; exit 0; }; done'
gate_path="$tmp/fakezero2:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G28k verdict call prints two words" block "could not compute"
shim fakeloose 'for a in "$@"; do [ "$a" = --rawfile ] && { echo OK; exit 0; }; done'
gate_path="$tmp/fakeloose:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G28l verdict call prints OK in upper case" block "could not compute"
unset gate_path

# ---- T-G31: NotebookEdit sends notebook_path (contract-gate-notebook.patch).
echo "# notebook_path"
if :; then  # always runs: there is no switch that skips a group
  jq -n --arg f "$proj/docs/contracts/tools.md" \
    '{tool_name:"NotebookEdit",tool_input:{notebook_path:$f,new_source:"status: approved",edit_mode:"replace"},cwd:"/nowhere"}' > "$tmp/in.json"
  run_gate $lim "$tmp/in.json"; expect "T-G31a NotebookEdit notebook_path on a contract" block "use Edit or Write"
  jq -n --arg f "$proj/.claude/hooks/x.ipynb" \
    '{tool_name:"NotebookEdit",tool_input:{notebook_path:$f,new_source:"x"},cwd:"/nowhere"}' > "$tmp/in.json"
  run_gate $lim "$tmp/in.json"; expect "T-G31b NotebookEdit notebook_path on a gate path" block "is a gate"
  jq -n --arg f "$proj/src/features/nocontract/a.ipynb" \
    '{tool_name:"NotebookEdit",tool_input:{notebook_path:$f,new_source:"x"},cwd:"/nowhere"}' > "$tmp/in.json"
  run_gate $lim "$tmp/in.json"; expect "T-G31c NotebookEdit notebook_path on feature code without a contract" block "has no contract"
fi

# ---- T-G32 (F1): doubled slashes, root forms, aliases and symlinked parents.
echo "# path forms"
mk_write_abs() { # mk_write_abs <absolute path> <content>
  printf '%s' "$2" > "$tmp/content.txt"
  jq -n --arg f "$1" --rawfile c "$tmp/content.txt" \
    '{tool_name:"Write",tool_input:{file_path:$f,content:$c},cwd:"/nowhere"}' > "$tmp/in.json"
}
appr="$(printf -- '---\nstatus: approved\n---\n# x\n')"
if :; then  # always runs
  put_contract pdraft draft
  for f in "/$proj/docs/contracts/pdraft.md" "$proj//docs/contracts/pdraft.md" "//$proj///docs//contracts/pdraft.md" "$proj/docs//contracts/pdraft.md"; do
    mk_write_abs "$f" "$appr"
    run_gate $lim "$tmp/in.json"; expect "T-G32a approve via '$f'" block "Only Dave approves"
  done
  for f in "/$proj/.claude/settings.json" "$proj//.claude/hooks/contract-gate.sh" "$proj/.claude//settings.json" "$proj///scripts/check-contracts.sh"; do
    mk_write_abs "$f" "x"
    run_gate $lim "$tmp/in.json"; expect "T-G32b gate via '$f'" block "is a gate"
  done
  mk_write_abs "/$proj/src/features/nocontract/a.ts" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32c feature code via a leading doubled slash" block "has no contract"
  # Root forms: trailing slash, doubled trailing slash, doubled inner slash.
  for r in "$proj/" "$proj//" "/$proj" "$(dirname "$proj")//proj"; do
    gate_root="$r"
    mk_write_abs "$proj/docs/contracts/pdraft.md" "$appr"
    run_gate $lim "$tmp/in.json"; expect "T-G32d root '$r', approve a contract" block "Only Dave approves"
    mk_write_abs "$proj/.claude/settings.json" "x"
    run_gate $lim "$tmp/in.json"; expect "T-G32d root '$r', gate file" block "is a gate"
    mk_write_str src/features/apprf/a.ts "x"
    run_gate $lim "$tmp/in.json"; expect "T-G32d root '$r', approved feature still allowed" allow
  done
  unset gate_root
  # Case-variant root. On a case-insensitive file system the contract is still read.
  gate_root="$(tr 'a-z' 'A-Z' <<<"$proj")"
  mk_write_abs "$proj/docs/contracts/pdraft.md" "$appr"
  run_gate $lim "$tmp/in.json"; expect "T-G32e upper-case root, approve a contract" block "Only Dave approves"
  mk_write_abs "$proj/.claude/settings.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32e upper-case root, gate file" block "is a gate"
  unset gate_root
  mk_write_abs "$(tr 'a-z' 'A-Z' <<<"$proj")/.claude/settings.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32e upper-case file path, gate file" block "is a gate"
  # macOS /private alias: /tmp and /var are symlinks to /private/tmp and /private/var.
  # Where that alias does not exist (Linux, or a fixture outside /private), a symlink to the temp dir stands in.
  alias_proj=""
  case "$proj" in /private/tmp/*|/private/var/*) [ -d "${proj#/private}" ] && alias_proj="${proj#/private}" ;; esac
  if [ -z "$alias_proj" ]; then
    alias_dir="$(dirname "$tmp")/cgt-alias.$$"; ln -s "$tmp" "$alias_dir"; alias_proj="$alias_dir/proj"
  fi
  case x in
    x)
      if [ -d "$alias_proj" ]; then
        mk_write_abs "$alias_proj/.claude/settings.json" "x"
        run_gate $lim "$tmp/in.json"; expect "T-G32f file via the alias $alias_proj, root physical" block "is a gate"
        mk_write_abs "$alias_proj/docs/contracts/pdraft.md" "$appr"
        run_gate $lim "$tmp/in.json"; expect "T-G32f contract via alias, root physical" block "Only Dave approves"
        gate_root="$alias_proj"
        mk_write_abs "$proj/.claude/settings.json" "x"
        run_gate $lim "$tmp/in.json"; expect "T-G32f root via alias, file physical" block "is a gate"
        mk_write_str src/features/apprf/a.ts "x"
        run_gate $lim "$tmp/in.json"; expect "T-G32f root via alias, approved feature still allowed" allow
        unset gate_root
      else bad "T-G32f the alias $alias_proj does not exist (test setup)"; fi ;;
  esac
  # Symlinked parents, outside and inside the root.
  mkdir -p "$proj/.claude/hooks"
  ln -s "$proj/.claude" "$tmp/outlink"
  mk_write_abs "$tmp/outlink/settings.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32g outside symlink to .claude" block "is a gate"
  ln -s "$proj/docs/contracts" "$tmp/outcontracts"
  mk_write_abs "$tmp/outcontracts/pdraft.md" "$appr"
  run_gate $lim "$tmp/in.json"; expect "T-G32g outside symlink to docs/contracts, approve" block "Only Dave approves"
  mk_write_abs "$tmp/outcontracts/pdraft.md" "$(printf -- '---\nstatus: draft\n---\n# x\n')"
  run_gate $lim "$tmp/in.json"; expect "T-G32g outside symlink to docs/contracts, draft" allow
  ln -s .claude "$proj/inlink"
  mk_write_abs "$proj/inlink/settings.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32h inside symlink to .claude" block "is a gate"
  ln -s ../.claude/hooks "$proj/docs/hk"
  mk_write_abs "$proj/docs/hk/new/deeper/x.sh" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32h inside symlink, missing subfolders below it" block "is a gate"
  # A symlinked file: the write lands on the link target.
  ln -s "$proj/.claude/settings.json" "$tmp/outfile.json"
  mk_write_abs "$tmp/outfile.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32m outside file symlink to settings.json" block "is a gate"
  ln -s ../.claude/settings.json "$proj/docs/note.json"
  mk_write_abs "$proj/docs/note.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32m inside file symlink to settings.json" block "is a gate"
  ln -s "$proj/docs/contracts/pdraft.md" "$tmp/outcontract.md"
  mk_write_abs "$tmp/outcontract.md" "$appr"
  run_gate $lim "$tmp/in.json"; expect "T-G32m outside file symlink to a contract, approve" block "Only Dave approves"
  ln -s "$tmp/loop2" "$tmp/loop1"; ln -s "$tmp/loop1" "$tmp/loop2"
  mk_write_abs "$tmp/loop1" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32m symlink loop outside the root" allow
  # Root reached through a symlink.
  ln -s "$proj" "$tmp/projlink"
  gate_root="$tmp/projlink"
  mk_write_abs "$proj/.claude/settings.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32i root via symlink, physical file path" block "is a gate"
  mk_write_abs "$tmp/projlink/.claude/settings.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32i root via symlink, file via the same symlink" block "is a gate"
  unset gate_root
  # Revision 3 checks the physical path in-process (no re-run, no second jq call). A jq that
  # fails on every call but the parse still cannot unblock a gate reached through a symlink.
  shim fakephys 'for a in "$@"; do [ "$a" = -rs ] && exec "'"$real_jq"'" "$@"; done; exit 1'
  gate_path="$tmp/fakephys:$PATH"
  mk_write_abs "$tmp/outlink/settings.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G32j symlink to .claude with only the parse jq working" block "is a gate"
  unset gate_path
  # Outside the root stays allowed, including with doubled slashes.
  mkdir -p "$tmp/else/docs/contracts"
  for f in "$tmp/else/docs/contracts/x.md" "/$tmp/else/.claude/settings.json" "$tmp//else/docs/contracts/x.md"; do
    mk_write_abs "$f" "$appr"
    run_gate $lim "$tmp/in.json"; expect "T-G32k outside the root '$f'" allow
  done
  # Dot segments still block in every form.
  for f in "$proj//docs/../.claude/settings.json" "/$tmp/../$(basename "$tmp")/proj/.claude/settings.json"; do
    mk_write_abs "$f" "x"
    run_gate $lim "$tmp/in.json"; expect "T-G32l dot segments '$f'" block "without . or .. segments"
  done
fi

# ---- Revision 3: findings A to G.
if :; then  # always runs
mkdir -p "$tmp/else"
mk_json() { # mk_json <jq expression>: --arg p (fixture root), e (outside dir) are available
  jq -n --arg p "$proj" --arg e "$tmp/else" "$1" > "$tmp/in.json"
}
mk_raw() { printf '%s' "$1" > "$tmp/in.json"; }

# ---- T-G33 (A): file system folding (U+017F to s, U+212A to k on APFS), and other names.
echo "# A: folded spellings and hard links"
fr="$tmp/fold-sk"
mkdir -p "$fr/.claude/hooks" "$fr/scripts" "$fr/.github/workflows" "$fr/docs/contracts" "$fr/src/features/draftf" "$fr/notes"
for g in .claude/settings.json .claude/hooks/contract-gate.sh scripts/check-contracts.sh .github/workflows/agent-gates.yml; do echo x > "$fr/$g"; done
printf -- '---\nstatus: approved\n---\n# approved\nBody.\n' > "$fr/docs/contracts/approved.md"
printf -- '---\nstatus: draft\n---\n# draft\nBody.\n' > "$fr/docs/contracts/draft.md"
printf -- '---\nstatus: draft\n---\n# draftf\n' > "$fr/docs/contracts/draftf.md"
S="$(printf '\305\277')"; K="$(printf '\342\204\252')"
mkdir -p "$fr/lib/features/draftf" "$fr/src/modules/draftf"
folds=0
if [ -e "$fr/.claude/${S}ettings.json" ]; then folds=1; echo "INFO: this file system folds U+017F to s, so folded writes land on the real file"
else echo "INFO: this file system does not fold U+017F; the folded cases still must block"; fi
gate_root="$fr"
nf=0
# Under the root every non-ASCII spelling blocks, folded by this file system or not. A gate found by
# inode says "is a gate"; any other name says "outside printable ASCII" before the contract rules run.
for r in .claude/settings.json .claude/hooks/contract-gate.sh .claude/hooks/new.sh scripts/check-contracts.sh \
  .github/workflows/agent-gates.yml docs/contracts/approved.md docs/contracts/draft.md docs/contracts/new.md \
  src/features/draftf/a.ts lib/features/draftf/a.dart src/modules/draftf/a.ts; do
  case "$r" in
    .claude/*|scripts/*|.github/*) fm="is a gate || outside printable ASCII" ;;
    *) fm="outside printable ASCII" ;;
  esac
  for ((i = 0; i < ${#r}; i++)); do
    c="${r:$i:1}"
    case "$c" in s) sub="$S" ;; k) sub="$K" ;; *) continue ;; esac
    v="${r:0:$i}$sub${r:$((i + 1))}"
    mk_write_abs "$fr/$v" "$appr"
    run_gate $lim "$tmp/in.json"; expect "T-G33a folded '$c' at $i in $r" block "$fm"
    nf=$((nf + 1))
  done
done
# Allow controls for the same area: plain ASCII names in the same folders.
for r in .claude/agents/new.md .claude/settings.local.json scripts/other.sh .github/workflows/ci.yml docs/notes.md docs/contracts/sub/x.md; do
  mk_write_abs "$fr/$r" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G33a control: ASCII name $r" allow
done
echo "INFO: $nf folded variants"
# The root itself spelled with a folded character, and a folded folder above the root.
for v in "$tmp/fold-${S}k" "$tmp/fold-s${K}" "$(dirname "$tmp")/$(basename "$tmp" | sed "s/test/te${S}t/")/fold-sk"; do
  if [ "$folds" = 1 ]; then
    # The file system maps the folded spelling to the root, so the write lands in the root.
    mk_write_abs "$v/.claude/settings.json" "x"
    run_gate $lim "$tmp/in.json"; expect "T-G33b folded root '$v', gate file" block "is a gate"
    mk_write_abs "$v/docs/contracts/draft.md" "$appr"
    run_gate $lim "$tmp/in.json"; expect "T-G33b folded root '$v', approve a draft contract" block "Only Dave approves"
    mk_write_abs "$v/src/features/draftf/a.ts" "x"
    run_gate $lim "$tmp/in.json"; expect "T-G33b folded root '$v', draft feature code" block "is not approved yet"
    mk_write_abs "$v/notes/plain.md" "x"
    run_gate $lim "$tmp/in.json"; expect "T-G33b control: folded root '$v', harmless file" allow
  else
    # No folding: the folded spelling is another folder, outside the root, and the hook must not
    # block it. (Folding file systems, such as APFS, run the branch above.)
    mk_write_abs "$v/.claude/settings.json" "x"
    run_gate $lim "$tmp/in.json"; expect "T-G33b non-folding file system: '$v' is another folder" allow
  fi
done
# Hard links to gate files and contracts, inside and outside the root.
ln "$fr/.claude/settings.json" "$fr/notes/s.json"
ln "$fr/.claude/hooks/contract-gate.sh" "$fr/notes/h.sh"
ln "$fr/.claude/settings.json" "$tmp/else/s2.json"
ln "$fr/docs/contracts/approved.md" "$fr/notes/a.md"
ln "$fr/docs/contracts/draft.md" "$tmp/else/d.md"
mk_write_abs "$fr/notes/s.json" "x"; run_gate $lim "$tmp/in.json"; expect "T-G33c hard link in the root to settings.json" block "is a gate"
mk_write_abs "$fr/notes/h.sh" "x"; run_gate $lim "$tmp/in.json"; expect "T-G33c hard link in the root to a hook" block "is a gate"
mk_write_abs "$tmp/else/s2.json" "x"; run_gate $lim "$tmp/in.json"; expect "T-G33c hard link outside the root to settings.json" block "is a gate"
mk_write_abs "$fr/notes/a.md" "$appr"; run_gate $lim "$tmp/in.json"; expect "T-G33c hard link to an approved contract, stays approved" block "is approved. Set status: draft"
mk_write_abs "$tmp/else/d.md" "$appr"; run_gate $lim "$tmp/in.json"; expect "T-G33c hard link outside the root to a draft contract, approve" block "Only Dave approves"
# Not over-blocked: ASCII in the root, non-ASCII outside the root (also a folded gate name there).
mk_write_abs "$fr/notes/plain.md" "x"; run_gate $lim "$tmp/in.json"; expect "T-G33d ASCII file in the root" allow
mk_write_abs "$tmp/else/caf$(printf '\303\251').md" "x"; run_gate $lim "$tmp/in.json"; expect "T-G33d non-ASCII file outside the root" allow
mkdir -p "$tmp/else/.claude"
mk_write_abs "$tmp/else/.claude/${S}ettings.json" "x"; run_gate $lim "$tmp/in.json"; expect "T-G33d folded gate name outside the root" allow
# Known false positive, by design: a legitimate non-ASCII name inside the root blocks.
mk_write_abs "$fr/notes/caf$(printf '\303\251').md" "x"; run_gate $lim "$tmp/in.json"; expect "T-G33e non-ASCII name in the root blocks (by design)" block "outside printable ASCII"
unset gate_root

# ---- T-G34 (B): NUL and other control characters.
echo "# B: NUL and control characters"
put_contract nul draft
mk_json '{tool_name:"Write",tool_input:{file_path:($p+"/docs/contracts/nul.md"),content:"---\n\u0000status: draft\nstatus: approved\n---\n"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G34a Write with a NUL line before status: approved" block "control character"
mk_json '{tool_name:"Write",tool_input:{file_path:($p+"/docs/contracts/nulnew.md"),content:"\u0000---\nstatus: approved\n"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G34a Write of a new contract with a leading NUL" block "control character"
mk_json '{tool_name:"Edit",tool_input:{file_path:($p+"/docs/contracts/nul.md"),old_string:"status: draft",new_string:"x\n\u0000\nstatus: approved"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G34b Edit new_string with NUL" block "control character"
mk_json '{tool_name:"Edit",tool_input:{file_path:($p+"/docs/contracts/nul.md"),old_string:"Body line one.\u0000",new_string:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G34c Edit old_string with NUL" block "control character"
printf -- '---\n\000status: draft\nstatus: approved\n---\nBody.\n' > "$proj/docs/contracts/nulcur.md"
echo "INFO: sed reads nulcur.md as '$(sed -n 's/^status:[[:space:]]*\([a-z]*\).*/\1/p' "$proj/docs/contracts/nulcur.md" | head -n 1)'"
mk_edit docs/contracts/nulcur.md "Body." "Body2."
run_gate $lim "$tmp/in.json"; expect "T-G34d current file with a NUL, approved body edit" block "NUL byte"
mk_write_str docs/contracts/nulcur.md "$(printf -- '---\nstatus: draft\n---\n')"
run_gate $lim "$tmp/in.json"; expect "T-G34d current file with a NUL, Write" block "NUL byte"
for u in 0001 0008 000b 000c 000e 001b 007f 0085 009f 2028 2029; do
  mk_json "{tool_name:\"Write\",tool_input:{file_path:(\$p+\"/docs/contracts/nul.md\"),content:\"---\\nstatus: draft\\n---\\nx\\u$u\\n\"},cwd:\"/nowhere\"}"
  run_gate $lim "$tmp/in.json"; expect "T-G34e Write with U+$u" block "control character"
  mk_json "{tool_name:\"Edit\",tool_input:{file_path:(\$p+\"/docs/contracts/nul.md\"),old_string:\"Body line one.\",new_string:\"x\\u${u}y\"},cwd:\"/nowhere\"}"
  run_gate $lim "$tmp/in.json"; expect "T-G34e Edit new_string with U+$u" block "control character"
done
mk_json '{tool_name:"Write",tool_input:{file_path:($p+"/docs/contracts/nul.md"),content:"---\r\nstatus: draft\r\n---\r\n\tindented\r\n"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G34f draft with tab and CRLF" allow
mk_json '{tool_name:"Write",tool_input:{file_path:($p+"/docs/contracts/nul.md"),content:"---\nx\rstatus: approved\n---\n"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G34g lone CR before status: approved" block "Only Dave approves"
mk_json '{tool_name:"Write",tool_input:{file_path:($p+"/docs/contracts/nul.md"),content:"---\nx\rstatus: draft\nstatus: Approved\n---\n"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G34g lone CR draft line, then a loose approved line" block "Only Dave approves"
for v in 'status:approved' 'status:\tapproved' 'status: approvedX' 'status: approved_1' 'status: approved\r' 'status: approved '; do
  mk_json "{tool_name:\"Write\",tool_input:{file_path:(\$p+\"/docs/contracts/nul.md\"),content:\"---\\n$v\\n---\\n\"},cwd:\"/nowhere\"}"
  run_gate $lim "$tmp/in.json"; expect "T-G34h strict reading of '$v'" block "Only Dave approves"
done
# A raw NUL byte in the JSON itself, inside content and inside file_path.
printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"a\000b"}}' "$proj/docs/contracts/nul.md" > "$tmp/in.json"
run_gate $lim "$tmp/in.json"; expect "T-G34i raw NUL byte inside content" block "could not read the tool input"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s\000x","content":"a"}}' "$proj/.claude/settings.json" > "$tmp/in.json"
run_gate $lim "$tmp/in.json"; expect "T-G34i raw NUL byte inside file_path" block "could not read the tool input"

# ---- T-G35 (C): NotebookEdit writes notebook_path; every path field present is checked.
echo "# C: NotebookEdit decoys"
mk_json '{tool_name:"NotebookEdit",tool_input:{notebook_path:($p+"/.claude/settings.json"),file_path:($e+"/x.txt"),new_source:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G35a NotebookEdit notebook_path gate, file_path harmless" block "is a gate"
mk_json '{tool_name:"NotebookEdit",tool_input:{notebook_path:($e+"/x.ipynb"),file_path:($p+"/.claude/settings.json"),new_source:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G35b NotebookEdit notebook_path harmless, file_path gate" block "is a gate"
mk_json '{tool_name:"Edit",tool_input:{file_path:($e+"/x.txt"),notebook_path:($p+"/.claude/hooks/x.sh"),old_string:"a",new_string:"b"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G35c Edit file_path harmless, notebook_path gate" block "is a gate"
mk_json '{tool_name:"NotebookEdit",tool_input:{notebook_path:($p+"/docs/contracts/tools.md"),file_path:($e+"/x.txt"),new_source:"status: approved"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G35d NotebookEdit notebook_path contract, file_path harmless" block "use Edit or Write"
mk_json '{tool_name:"NotebookEdit",tool_input:{file_path:($e+"/x.ipynb"),new_source:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G35e NotebookEdit without notebook_path" block "no path field"
mk_json '{tool_name:"Edit",tool_input:{notebook_path:($e+"/x.ipynb"),old_string:"a",new_string:"b"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G35e Edit without file_path" block "no path field"
mk_json '{tool_name:"NotebookEdit",tool_input:{notebook_path:($e+"/x.ipynb"),new_source:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G35f NotebookEdit outside the root" allow
mk_json '{tool_name:"NotebookEdit",tool_input:{notebook_path:($p+"/src/features/apprf/n.ipynb"),new_source:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G35f NotebookEdit on approved feature code" allow
mk_json '{tool_name:"NotebookEdit",tool_input:{notebook_path:($p+"/src/features/draftf/n.ipynb"),new_source:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G35f NotebookEdit on draft feature code" block "is not approved yet"

# ---- T-G36 (D): no re-run, so neither a failing jq nor CONTRACT_GATE_PHYSICAL can switch the check off.
echo "# D: physical check in-process"
mkdir -p "$proj/.claude"; [ -f "$proj/.claude/settings.json" ] || echo x > "$proj/.claude/settings.json"
ln -s "$proj/.claude/settings.json" "$proj/docs/settings-link.json"
shim fakechild 'if [ -n "${CONTRACT_GATE_PHYSICAL:-}" ]; then exit 1; fi'
gate_path="$tmp/fakechild:$PATH"
mk_write_abs "$proj/docs/settings-link.json" "x"
run_gate $lim "$tmp/in.json"; expect "T-G36a jq fails only under CONTRACT_GATE_PHYSICAL, symlink to settings.json" block "is a gate"
export CONTRACT_GATE_PHYSICAL=1
run_gate $lim "$tmp/in.json"; expect "T-G36b same, with CONTRACT_GATE_PHYSICAL=1 preset (the shim now fails every jq call)" block "contract-gate:"
unset gate_path
run_gate $lim "$tmp/in.json"; expect "T-G36b CONTRACT_GATE_PHYSICAL=1 preset, symlink to settings.json" block "is a gate"
mk_write_abs "$tmp/outcontracts/pdraft.md" "$appr"
run_gate $lim "$tmp/in.json"; expect "T-G36b CONTRACT_GATE_PHYSICAL=1 preset, outside symlink to contracts, approve" block "Only Dave approves"
mk_write_abs "$tmp/outlink/settings.json" "x"
run_gate $lim "$tmp/in.json"; expect "T-G36b CONTRACT_GATE_PHYSICAL=1 preset, outside symlink to .claude" block "is a gate"
unset CONTRACT_GATE_PHYSICAL
mk_write_abs "$proj/docs/settings-link.json" "x"
shim fakeparse 'for a in "$@"; do [ "$a" = -rs ] && exit 1; done'
gate_path="$tmp/fakeparse:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G36c parse jq fails" block "could not read the tool input"
shim fakeparse0 'for a in "$@"; do [ "$a" = -rs ] && exit 0; done'
gate_path="$tmp/fakeparse0:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G36c parse jq prints nothing" block "could not read the tool input"
shim fakeparse1 'for a in "$@"; do [ "$a" = -rs ] && { echo OK; exit 0; }; done'
gate_path="$tmp/fakeparse1:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G36c parse jq prints only OK" block "could not read the tool input"
unset gate_path

# ---- T-G37 (E): bad input fails closed.
echo "# E: bad input"
gw="$proj/.claude/settings.json"
n=0
for j in '{bad' '' '[]' '"x"' '{}' '{"tool_name":"Write"}' '{"tool_name":"Write","tool_input":"x"}' \
  '{"tool_name":"Write","tool_input":{"file_path":5}}' '{"tool_name":"Write","tool_input":{"file_path":null}}' \
  '{"tool_name":"Write","tool_input":{"file_path":""}}' '{"tool_name":"Write","tool_input":{"file_path":["a"]}}' \
  '{"tool_name":"Write","tool_input":{"file_path":{"a":1}}}' '{"tool_name":"Write","tool_input":{"content":"x"}}' \
  "{\"tool_name\":5,\"tool_input\":{\"file_path\":\"$gw\"}}" \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$gw\"},\"cwd\":5}" \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp/else/x\"}} {\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$gw\"}}" \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$gw\\nx\"}}" \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp/else/x\\u0007\"}}"; do
  n=$((n + 1)); mk_raw "$j"
  run_gate $lim "$tmp/in.json"; expect "T-G37a bad input $n: $(printf '%s' "$j" | head -c 60)" block "contract-gate:"
done
gate_root=""
mk_raw "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$gw\",\"content\":\"x\"}}"
run_gate $lim "$tmp/in.json"; expect "T-G37b no root and no cwd, absolute gate path" block "no project root"
mk_raw "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp/else/x.txt\",\"content\":\"x\"}}"
run_gate $lim "$tmp/in.json"; expect "T-G37b no root and no cwd, absolute harmless path" block "no project root"
mk_raw '{"tool_name":"Write","tool_input":{"file_path":"notes/x.txt","content":"x"}}'
run_gate $lim "$tmp/in.json"; expect "T-G37c no root and no cwd, relative path" allow
mk_raw "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$gw\",\"content\":\"x\"},\"cwd\":\"$proj\"}"
run_gate $lim "$tmp/in.json"; expect "T-G37d empty CLAUDE_PROJECT_DIR, root from cwd, gate file" block "is a gate"
mk_raw "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$proj/src/features/apprf/a.ts\",\"content\":\"x\"},\"cwd\":\"$proj\"}"
run_gate $lim "$tmp/in.json"; expect "T-G37d empty CLAUDE_PROJECT_DIR, root from cwd, approved feature" allow
unset gate_root

# ---- T-G38 (F): /x/... becomes a drive only on Windows.
echo "# F: single-letter root"
normsrc="$(sed -n '/^norm() {/,/^}/p' "$GATE")"
if [ -z "$normsrc" ]; then bad "T-G38a norm() not found in $GATE"
else
  got="$(win=0; eval "$normsrc"; norm /w/proj; printf '|'; norm '/w/proj//docs/'; printf '|'; norm 'C:\x\y')"
  [ "$got" = "/w/proj|/w/proj/docs|C:/x/y" ] && ok "T-G38a norm off Windows keeps /w/proj ($got)" || bad "T-G38a norm off Windows: $got"
  got="$(win=1; eval "$normsrc"; norm /w/proj; printf '|'; norm 'C:\x\y'; printf '|'; norm '/c/Users/x/')"
  [ "$got" = "w:/proj|c:/x/y|c:/Users/x" ] && ok "T-G38a norm on Windows converts ($got)" || bad "T-G38a norm on Windows: $got"
fi
mkdir -p "$tmp/fakeuname"; printf '#!/bin/sh\necho MINGW64_NT-10.0-19045\n' > "$tmp/fakeuname/uname"; chmod +x "$tmp/fakeuname/uname"
gate_root="/c/fixproj"
mk_raw '{"tool_name":"Write","tool_input":{"file_path":"C:\\fixproj\\.claude\\settings.json","content":"x"}}'
gate_path="$tmp/fakeuname:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G38b Windows (fake uname), MSYS root, drive-form gate path" block "is a gate"
mk_raw '{"tool_name":"Write","tool_input":{"file_path":"/C/fixproj/docs/../x","content":"x"}}'
run_gate $lim "$tmp/in.json"; expect "T-G38b Windows (fake uname), dot segments" block "without . or .. segments"
unset gate_path
mk_raw '{"tool_name":"Write","tool_input":{"file_path":"C:\\fixproj\\.claude\\settings.json","content":"x"}}'
run_gate $lim "$tmp/in.json"; expect "T-G38c not Windows, drive-form path blocks" block "Windows drive path"
gate_root='C:\fixproj'
run_gate $lim "$tmp/in.json"; expect "T-G38d drive-form root, drive-form gate path" block "is a gate"
mk_raw '{"tool_name":"Write","tool_input":{"file_path":"/c/fixproj/.claude/settings.json","content":"x"}}'
run_gate $lim "$tmp/in.json"; expect "T-G38d drive-form root, /c/ gate path" block "is a gate"
unset gate_root
# T-G38e: a single-letter root such as /w/fixproj or /w, as on Linux. The folder need not exist:
# the checks are lexical for a missing path, and nothing is created outside the temp dir.
for gr in /w/fixproj /w /w/fixproj/; do
  gate_root="$gr"; b="${gr%/}"
  mk_write_abs "$b/.claude/settings.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G38e root '$gr', gate file" block "is a gate"
  mk_write_abs "$b/docs/contracts/new.md" "$appr"
  run_gate $lim "$tmp/in.json"; expect "T-G38e root '$gr', approve a new contract" block "Only Dave approves"
  mk_write_abs "$b/src/features/foo/a.ts" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G38e root '$gr', feature code without a contract" block "has no contract"
  mk_write_abs "$b/notes/x.txt" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G38e root '$gr', harmless file" allow
  mk_write_abs "/x/outside/.claude/settings.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G38e root '$gr', another single-letter folder outside the root" allow
done
unset gate_root
# A drive-form path in a second field must not switch the physical check off for the real path.
mk_json '{tool_name:"NotebookEdit",tool_input:{notebook_path:($p+"/.claude/settings.json"),file_path:"C:x",new_source:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G38f drive-form decoy in file_path, gate in notebook_path" block "Windows drive path || is a gate"
mk_json '{tool_name:"NotebookEdit",tool_input:{notebook_path:($e+"/x.ipynb"),file_path:"C:x",new_source:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G38f drive-form second field, harmless notebook_path" block "Windows drive path"

# ---- T-G41: symlinks inside the root to contracts and feature folders, F2 and F3 through them.
echo "# inside symlinks to contracts and feature folders"
mkdir -p "$proj/src/features/draftf" "$proj/src/features/apprf" "$proj/notes" "$proj/lib/features"
put_contract apprc approved
put_contract pdraft draft
ln -s docs/contracts "$proj/cl"
ln -s src/features "$proj/sf"
ln -s ../src/features/draftf "$proj/notes/fd"
ln -s ../src/features/apprf "$proj/notes/fa"
ln -s ../docs/contracts/pdraft.md "$proj/notes/cfile.md"
ln -s cfile.md "$proj/notes/cchain.md"
ln -s notes "$proj/nl"
mk_tool() { # mk_tool <tool> <absolute path> [old_string]: an Edit-shaped call by any tool name
  jq -n --arg t "$1" --arg f "$2" --arg o "${3-Body line one.}" \
    '{tool_name:$t,tool_input:{file_path:$f,old_string:$o,new_string:"B",content:"x"},cwd:"/nowhere"}' > "$tmp/in.json"
}
mk_write_abs "$proj/cl/pdraft.md" "$appr"
run_gate $lim "$tmp/in.json"; expect "T-G41a folder symlink to docs/contracts, approve a draft" block "Only Dave approves"
mk_write_abs "$proj/cl/brandnew41.md" "$appr"
run_gate $lim "$tmp/in.json"; expect "T-G41a folder symlink to docs/contracts, new contract as approved" block "Only Dave approves"
mk_write_abs "$proj/cl/pdraft.md" "$(printf -- '---\nstatus: draft\n---\n# x\n')"
run_gate $lim "$tmp/in.json"; expect "T-G41a control: folder symlink to docs/contracts, draft stays draft" allow
mk_edit cl/apprc.md "Body line one." "Body line one, changed."
run_gate $lim "$tmp/in.json"; expect "T-G41b approved contract edited through the folder symlink, no reopen" block "is approved. Set status: draft"
mk_edit cl/apprc.md "status: approved" "status: draft"
run_gate $lim "$tmp/in.json"; expect "T-G41b control: approved contract reopened through the folder symlink" allow
mk_write_abs "$proj/notes/cfile.md" "$appr"
run_gate $lim "$tmp/in.json"; expect "T-G41c file symlink to a contract, approve" block "Only Dave approves"
mk_write_abs "$proj/notes/cchain.md" "$appr"
run_gate $lim "$tmp/in.json"; expect "T-G41c chain of file symlinks to a contract, approve" block "Only Dave approves"
mk_write_abs "$proj/sf/draftf/a.ts" "x"
run_gate $lim "$tmp/in.json"; expect "T-G41d symlink to src/features, draft feature" block "is not approved yet"
mk_write_abs "$proj/notes/fd/a.ts" "x"
run_gate $lim "$tmp/in.json"; expect "T-G41d symlink to one draft feature folder" block "is not approved yet"
mk_write_abs "$proj/sf/nocontract41/a.ts" "x"
run_gate $lim "$tmp/in.json"; expect "T-G41d symlink to src/features, feature with no contract" block "has no contract"
mk_write_abs "$proj/sf/apprf/a.ts" "x"
run_gate $lim "$tmp/in.json"; expect "T-G41d control: symlink to src/features, approved feature" allow
mk_write_abs "$proj/notes/fa/a.ts" "x"
run_gate $lim "$tmp/in.json"; expect "T-G41d control: symlink to one approved feature folder" allow
mk_write_abs "$proj/nl/x.txt" "x"
run_gate $lim "$tmp/in.json"; expect "T-G41d control: symlink to a harmless folder" allow
# F2: empty old_string on an existing contract, through links.
mk_edit cl/apprc.md "" "$(printf -- '---\nstatus: draft\n---\n')"
run_gate $lim "$tmp/in.json"; expect "T-G41e F2 empty old_string through the folder symlink" block "empty old_string on existing docs/contracts/apprc.md"
mk_edit notes/cfile.md "" "$(printf -- '---\nstatus: draft\n---\n')"
run_gate $lim "$tmp/in.json"; expect "T-G41e F2 empty old_string through a file symlink" block "empty old_string on existing docs/contracts/pdraft.md"
# F3: any tool but Edit and Write, through links.
for t in MultiEdit NotebookEdit edit; do
  mk_tool "$t" "$proj/cl/pdraft.md"
  if [ "$t" = NotebookEdit ]; then jq '.tool_input.notebook_path = .tool_input.file_path' "$tmp/in.json" > "$tmp/in2.json" && mv "$tmp/in2.json" "$tmp/in.json"; fi
  run_gate $lim "$tmp/in.json"; expect "T-G41f F3 tool '$t' through the folder symlink" block "use Edit or Write on docs/contracts/pdraft.md"
  mk_tool "$t" "$proj/notes/cchain.md"
  if [ "$t" = NotebookEdit ]; then jq '.tool_input.notebook_path = .tool_input.file_path' "$tmp/in.json" > "$tmp/in2.json" && mv "$tmp/in2.json" "$tmp/in.json"; fi
  run_gate $lim "$tmp/in.json"; expect "T-G41f F3 tool '$t' through a file symlink chain" block "use Edit or Write on docs/contracts/pdraft.md"
done
mk_tool NotebookEdit "$proj/notes/x.ipynb"; jq '.tool_input.notebook_path = .tool_input.file_path | del(.tool_input.file_path)' "$tmp/in.json" > "$tmp/in2.json" && mv "$tmp/in2.json" "$tmp/in.json"
run_gate $lim "$tmp/in.json"; expect "T-G41f control: NotebookEdit on a harmless notebook" allow
ln -s "$proj/.claude/settings.json" "$proj/notes/nbs.ipynb"
mk_tool NotebookEdit "$proj/notes/nbs.ipynb"; jq '.tool_input.notebook_path = .tool_input.file_path | del(.tool_input.file_path)' "$tmp/in.json" > "$tmp/in2.json" && mv "$tmp/in2.json" "$tmp/in.json"
run_gate $lim "$tmp/in.json"; expect "T-G41g NotebookEdit notebook_path symlink to settings.json" block "is a gate"

# ---- T-G42: old_string and new_string are literal text, never a pattern or a replacement template.
echo "# literal old_string and new_string"
printf -- '---\nstatus: draft\n---\n# meta\nabc\na.c (x) [y]* \\d $ ^ | ? + {2}\n' > "$proj/docs/contracts/meta.md"
mk_edit docs/contracts/meta.md 'a.c (x) [y]* \d $ ^ | ? + {2}' 'plain'
run_gate $lim "$tmp/in.json"; expect "T-G42a old_string with every regex metacharacter, exact text" allow
mk_edit docs/contracts/meta.md '.*' 'x'
run_gate $lim "$tmp/in.json"; expect "T-G42b old_string '.*' is not a pattern" block "must match docs/contracts/meta.md exactly"
mk_edit docs/contracts/meta.md 'status: d.aft' 'status: approved'
run_gate $lim "$tmp/in.json"; expect "T-G42c old_string 'status: d.aft' is not a pattern" block "must match docs/contracts/meta.md exactly"
mk_edit docs/contracts/meta.md 'status: [a-z]+' 'status: approved'
run_gate $lim "$tmp/in.json"; expect "T-G42d old_string 'status: [a-z]+' is not a pattern" block "must match docs/contracts/meta.md exactly"
mk_edit docs/contracts/meta.md 'a(b)?c' 'x'
run_gate $lim "$tmp/in.json"; expect "T-G42e old_string 'a(b)?c' is not a pattern" block "must match docs/contracts/meta.md exactly"
mk_edit docs/contracts/meta.md 'abc' '\1 & $& \0 \\ $1 ${x}'
run_gate $lim "$tmp/in.json"; expect "T-G42f new_string with replacement-template characters is inserted as is" allow
mk_edit docs/contracts/meta.md 'status: draft' 'status: approved'
run_gate $lim "$tmp/in.json"; expect "T-G42g control: literal draft to approved" block "Only Dave approves"
mk_edit docs/contracts/meta.md 'abc' 'status: \1pproved' 
run_gate $lim "$tmp/in.json"; expect "T-G42h control: template text does not become 'approved'" allow

# ---- T-G43: feature roots lib/features and src/modules, and what is not feature code.
echo "# feature roots"
for area in lib/features src/features src/modules; do
  f43="f43$(printf '%s' "$area" | tr -d '/')"
  mk_write_str "$area/$f43/a.x" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G43a $area, no contract and no folder" block "New feature '$f43' has no contract"
  put_contract "$f43" draft
  run_gate $lim "$tmp/in.json"; expect "T-G43b $area, draft contract" block "docs/contracts/$f43.md is not approved yet"
  put_contract "$f43" approved
  run_gate $lim "$tmp/in.json"; expect "T-G43c $area, approved contract" allow
  rm -f "$proj/docs/contracts/$f43.md"
  mkdir -p "$proj/$area/$f43"
  run_gate $lim "$tmp/in.json"; expect "T-G43d $area, no contract but the feature folder already exists" allow
  mk_write_str "$area/$f43/deep/er/b.x" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G43d $area, nested file in an existing feature" allow
  mk_write_str "$area/nocontract43/deep/er/b.x" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G43e $area, nested file in a new feature" block "New feature 'nocontract43' has no contract"
  mk_write_str "$area/file43.x" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G43f $area, a file directly in the area is not a feature" allow
done
for r in lib/main.dart src/main.ts src/featuresX/y/a.ts src/feature/y/a.ts src/module/y/a.ts lib/feature/y/a.dart docs/features/y/a.md; do
  mk_write_str "$r" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G43g not feature code: $r" allow
done
mk_write_str "SRC/FEATURES/draftf/a.ts" "x"
run_gate $lim "$tmp/in.json"; expect "T-G43h upper-case area, draft feature" block "is not approved yet"
mk_write_str "src/features/DRAFTF/a.ts" "x"
run_gate $lim "$tmp/in.json"; expect "T-G43h upper-case feature name resolves the same contract or none" block "is not approved yet || has no contract"

# ---- T-G44: which paths are contracts.
echo "# contract path shapes"
put_contract shape draft
printf -- '---\nstatus: draft\n---\n# x\n' > "$proj/docs/contracts/.hidden.md"
for r in docs/contracts/new44.md docs/contracts/X44.MD docs/contracts/X44.Md "docs/contracts/my plan.md" docs/contracts/.hidden.md \
  DOCS/CONTRACTS/shape.md Docs/Contracts/shape.md "docs/contracts/shape.md/" docs/contracts/a.b.c.md; do
  mk_write_str "$r" "$appr"
  run_gate $lim "$tmp/in.json"; expect "T-G44a approve '$r'" block "Only Dave approves"
done
for r in docs/contracts/sub/x.md docs/contracts/x.md.bak docs/contracts/x.mdx docs/contracts/x.txt docs/contracts-old/x.md docs/contract/x.md \
  xdocs/contracts/x.md docs/contracts.md docs/x/contracts/x.md contracts/x.md; do
  mk_write_str "$r" "$appr"
  run_gate $lim "$tmp/in.json"; expect "T-G44b control: '$r' is not a contract" allow
done
mk_write_str docs/contracts/my\ plan.md "$(printf -- '---\nstatus: draft\n---\n')"
run_gate $lim "$tmp/in.json"; expect "T-G44c control: contract with a space in its name, draft" allow

# ---- T-G45: backslash, drive-letter, UNC and relative paths.
echo "# backslash and drive paths"
for f in "$proj\\docs\\contracts\\shape.md" "$proj/docs\\contracts/shape.md" "$proj\\\\docs\\\\contracts\\\\shape.md" "${proj}\\docs/contracts\\\\shape.md"; do
  mk_write_abs "$f" "$appr"
  run_gate $lim "$tmp/in.json"; expect "T-G45a backslashes, approve '$f'" block "Only Dave approves"
done
for f in "$proj\\.claude\\settings.json" "$proj\\.claude\\hooks\\x.sh" "$proj/scripts\\check-contracts.sh" "$proj\\.github\\workflows\\agent-gates.yml"; do
  mk_write_abs "$f" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G45b backslashes, gate '$f'" block "is a gate"
done
mk_write_abs "$proj\\src\\features\\draftf\\a.ts" "x"
run_gate $lim "$tmp/in.json"; expect "T-G45c backslashes, draft feature" block "is not approved yet"
mk_write_abs "$proj\\notes\\x.txt" "x"
run_gate $lim "$tmp/in.json"; expect "T-G45d control: backslashes, harmless file" allow
mk_write_abs "$tmp\\else\\x.txt" "x"
run_gate $lim "$tmp/in.json"; expect "T-G45d control: backslashes, outside the root" allow
for f in 'C:\x\.claude\settings.json' 'c:/x/y' 'Z:foo' 'C:x'; do
  mk_raw "$(jq -n --arg f "$f" '{tool_name:"Write",tool_input:{file_path:$f,content:"x"}}')"
  run_gate $lim "$tmp/in.json"; expect "T-G45e drive-letter path '$f' off Windows" block "Windows drive path"
done
gate_root='\\server\share\proj'
mk_raw "$(jq -n '{tool_name:"Write",tool_input:{file_path:"\\\\server\\share\\proj\\.claude\\settings.json",content:"x"}}')"
run_gate $lim "$tmp/in.json"; expect "T-G45f UNC root, UNC gate path" block "is a gate"
mk_raw "$(jq -n '{tool_name:"Write",tool_input:{file_path:"\\\\server\\share\\proj\\notes\\x.txt",content:"x"}}')"
run_gate $lim "$tmp/in.json"; expect "T-G45f control: UNC root, harmless file" allow
unset gate_root
# Relative paths are read against the root. With cwd = root they are exact.
mk_raw '{"tool_name":"Write","tool_input":{"file_path":".claude/settings.json","content":"x"}}'
run_gate $lim "$tmp/in.json"; expect "T-G45g relative gate path" block "is a gate"
mk_raw "$(jq -n --arg a "$appr" '{tool_name:"Write",tool_input:{file_path:"docs/contracts/shape.md",content:$a}}')"
run_gate $lim "$tmp/in.json"; expect "T-G45g relative contract path, approve" block "Only Dave approves"
mk_raw '{"tool_name":"Write","tool_input":{"file_path":"notes/x.txt","content":"x"}}'
run_gate $lim "$tmp/in.json"; expect "T-G45g control: relative harmless path" allow
# A relative path against a cwd below the root is not the root's path. Gap, not asserted as a failure.
mk_raw "$(jq -n --arg c "$proj/docs" --arg a "$appr" '{tool_name:"Write",tool_input:{file_path:"contracts/shape.md",content:$a},cwd:$c}')"
run_gate $lim "$tmp/in.json"
if [ "$hung" -eq 0 ] && [ "$rc" -eq 2 ]; then ok "T-G45h relative contract path with cwd below the root blocks"
else known "T-G45h relative path 'contracts/shape.md' with cwd = <root>/docs is read against the root and allowed (Edit and Write send absolute paths)"; fi

# ---- T-G46: the verdict call prints something that is not exactly one known word.
echo "# verdict call output"
put_contract v46 draft
mk_edit docs/contracts/v46.md "Body line one." "Body line one, changed."
run_gate $lim "$tmp/in.json"; expect "T-G46 control: the allowed edit itself" allow
n=0
for w in 1 2 -1 abc ok. 'ok ok' ' ok' 'ok ' 'ok	' OK Ok approve1 nomatch2 ctl2 'field' reopen2 ' ' '"ok"' 'ok;'; do
  n=$((n + 1)); mkdir -p "$tmp/vw$n"
  { echo '#!/bin/sh'; echo 'for a in "$@"; do [ "$a" = --rawfile ] && { printf "%s\n" "$VW"; exit 0; }; done'; echo "exec \"$real_jq\" \"\$@\""; } > "$tmp/vw$n/jq"
  chmod +x "$tmp/vw$n/jq"
  gate_path="$tmp/vw$n:$PATH"; export VW="$w"
  run_gate $lim "$tmp/in.json"; expect "T-G46 verdict call prints '$w'" block "could not compute"
done
unset VW gate_path
# A good word with a failing exit code, and with noise on stderr, also fails closed or passes on the word.
shim fakeokfail 'for a in "$@"; do [ "$a" = --rawfile ] && { echo ok; exit 1; }; done'
gate_path="$tmp/fakeokfail:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G46 verdict call prints ok and exits 1" block "could not compute"
shim fakeoksig 'for a in "$@"; do [ "$a" = --rawfile ] && { echo ok; exit 3; }; done'
gate_path="$tmp/fakeoksig:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G46 verdict call prints ok and exits 3" block "could not compute"
shim fakeappr 'for a in "$@"; do [ "$a" = --rawfile ] && { echo approve; exit 0; }; done'
gate_path="$tmp/fakeappr:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G46 control: verdict word 'approve' blocks as an approval" block "Only Dave approves"
shim fakereopen 'for a in "$@"; do [ "$a" = --rawfile ] && { echo reopen; exit 0; }; done'
gate_path="$tmp/fakereopen:$PATH"
run_gate $lim "$tmp/in.json"; expect "T-G46 control: verdict word 'reopen' blocks as a reopen" block "is approved. Set status: draft"
unset gate_path
# The contract file cannot be passed to jq: jq missing from PATH for the verdict only is covered by T-G24; jq missing entirely:
mkdir -p "$tmp/nojq"; for b in tr sed uname cat head wc awk readlink dirname basename mktemp; do p="$(command -v $b || true)"; [ -n "$p" ] && ln -sf "$p" "$tmp/nojq/$b"; done
gate_path="$tmp/nojq"
run_gate $lim "$tmp/in.json"; expect "T-G46 jq missing from PATH" block "jq is required"
unset gate_path
# replace_all values beyond T-G27: the result must be the strictest reading, never looser than the first match.
printf -- '---\ntitle: draft plan\nstatus: draft\n---\n# mxa\n' > "$proj/docs/contracts/mxa.md"
for v in '[]' '{}' '"yes"' '-1' '1.5' '[true]' '{"a":true}' '"TRUE"'; do
  mk_ra docs/contracts/mxa.md draft approved "$v"
  run_gate $lim "$tmp/in.json"; expect "T-G46b replace_all=$v, draft to approved" block "Only Dave approves"
  mk_ra docs/contracts/mxa.md "plan" "plan2" "$v"
  run_gate $lim "$tmp/in.json"; expect "T-G46b control: replace_all=$v, harmless edit" allow
done

# ---- T-G47: bad input, more shapes. Each fails closed with the hook's own message.
echo "# bad input, more shapes"
gw="$proj/.claude/settings.json"
n=0
for j in 'null' '1' 'true' '{"tool_name":"Write","tool_input":null}' '{"tool_name":"Write","tool_input":[]}'   '{"tool_name":["Write"],"tool_input":{"file_path":"/x"}}' '{"tool_name":"Write","tool_input":{"file_path":true}}' '{"tool_name":"Write","tool_input":{"file_path":0}}' \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$gw\\u0000\"}}" "{\"tool_name\":\"Wri\\u0000te\",\"tool_input\":{\"file_path\":\"$gw\"}}" \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$gw\"},\"cwd\":\"$proj\\n\"}" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$gw\"},\"cwd\":[]}" \
  '{"tool_name":"Write","tool_input":{"file_path":"/x"}' \
  '{"tool_name":"Write","tool_input":{"file_path":"/x"}}}' 'garbage' '   ' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$gw\"}}{" \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp/else/x\",\"notebook_path\":5}}" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp/else/x\",\"notebook_path\":\"\"}}"; do
  n=$((n + 1)); mk_raw "$j"
  run_gate $lim "$tmp/in.json"; expect "T-G47a bad input $n: $(printf '%s' "$j" | head -c 70)" block "contract-gate:"
done
: > "$tmp/in.json"
run_gate $lim "$tmp/in.json"; expect "T-G47b empty stdin file" block "contract-gate:"
printf '\377\376{"tool_name":"Write"}' > "$tmp/in.json"
run_gate $lim "$tmp/in.json"; expect "T-G47b invalid UTF-8 bytes around the JSON" block "contract-gate:"
head -c 4096 /dev/urandom > "$tmp/in.json" 2>/dev/null || printf 'random' > "$tmp/in.json"
run_gate $lim "$tmp/in.json"; expect "T-G47b random bytes" block "contract-gate:"
# Control: the same call, well formed.
mk_raw "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$proj/notes/ok47.txt\",\"content\":\"x\"}}"
run_gate $lim "$tmp/in.json"; expect "T-G47 control: well-formed call, harmless path" allow
# Roots that do not exist: the checks are lexical, and a path below the root still is a gate.
for gr in "/nonexistent47/proj" "$tmp/else/nofolder47/proj"; do
  gate_root="$gr"
  mk_write_abs "$gr/.claude/settings.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G47c missing root '$gr', gate file" block "is a gate"
  mk_write_abs "$gr/docs/contracts/new47.md" "$appr"
  run_gate $lim "$tmp/in.json"; expect "T-G47c missing root '$gr', approve a new contract" block "Only Dave approves"
  mk_write_abs "$gr/notes/ok47.txt" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G47c control: missing root '$gr', harmless file" allow
done
# Roots spelled with dot segments or through a symlink: the real paths are still found by inode.
for gr in "$proj/../proj" "$proj/./" "$tmp/projlink/../proj"; do
  gate_root="$gr"
  mk_write_abs "$proj/.claude/settings.json" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G47c root '$gr', gate file by its real path" block "is a gate"
  mk_write_abs "$proj/docs/contracts/pdraft.md" "$appr"
  run_gate $lim "$tmp/in.json"; expect "T-G47c root '$gr', approve a draft by its real path" block "Only Dave approves"
  mk_write_abs "$proj/notes/ok47.txt" "x"
  run_gate $lim "$tmp/in.json"; expect "T-G47c control: root '$gr', harmless real path" allow
done
unset gate_root
# A plain file as the root: nothing is under it, so nothing is a gate, and nothing breaks.
echo x > "$tmp/plainfile47"
gate_root="$tmp/plainfile47"
mk_write_abs "$tmp/plainfile47/.claude/settings.json" "x"
run_gate $lim "$tmp/in.json"; expect "T-G47d root is a plain file, path below it" block "is a gate"
unset gate_root

# ---- T-G48: NUL and other control characters, more shapes.
echo "# NUL and control characters, more shapes"
mk_json '{tool_name:"Write",tool_input:{file_path:($p+"/src/features/apprf/bin.dat"),content:"a\u0000b\u0001c"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G48a control: NUL in the content of a non-contract file" allow
mk_json '{tool_name:"Write",tool_input:{file_path:($p+"/docs/contracts/nul.md"),content:"---\nstatus: draft\n---\nok\u0000"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G48b trailing NUL in a contract Write" block "control character"
mk_json '{tool_name:"Edit",tool_input:{file_path:($p+"/docs/contracts/nul.md"),old_string:"Body line one.",new_string:"\u0000"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G48b new_string that is only a NUL" block "control character"
mk_json '{tool_name:"Edit",tool_input:{file_path:($p+"/docs/contracts/nul.md"),old_string:"\u0000",new_string:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G48b old_string that is only a NUL" block "control character"
mk_json '{tool_name:"Edit",tool_input:{file_path:($p+"/docs/contracts/nul.md"),old_string:"",new_string:"\u0000status: approved"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G48b empty old_string, new_string with a NUL" block "control character"
# A contract that already holds other control characters (not NUL) can still be edited when it is a draft.
printf -- '---\nstatus: draft\n---\n# ctl\nBody\001 line.\n' > "$proj/docs/contracts/ctlcur.md"
mk_edit docs/contracts/ctlcur.md "Body" "Body2"
run_gate $lim "$tmp/in.json"; expect "T-G48c control: draft contract that already holds U+0001, harmless edit" allow
mk_edit docs/contracts/ctlcur.md "status: draft" "status: approved"
run_gate $lim "$tmp/in.json"; expect "T-G48c draft contract with U+0001, draft to approved" block "Only Dave approves"
# NUL as the only difference in the current file, at the start, the end, and inside the status line.
for pat in '\000---\nstatus: draft\n---\nBody\n' '---\nstatus: draft\n---\nBody\n\000' '---\nstat\000us: approved\n---\nBody\n' '---\nstatus: dra\000ft\n---\nBody\n'; do
  printf -- "$pat" > "$proj/docs/contracts/nulcur2.md"
  mk_edit docs/contracts/nulcur2.md "Body" "Body2"
  run_gate $lim "$tmp/in.json"; expect "T-G48d current contract with a NUL ($pat)" block "contains a NUL byte"
done
# Non-NUL control characters: tab, LF and CR pass; C1, LS and PS block (already in T-G34e). Allow control:
mk_json '{tool_name:"Write",tool_input:{file_path:($p+"/docs/contracts/nul.md"),content:"---\nstatus: draft\n---\n\ttab\r\ncrlf\n"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G48e control: tab, CR and LF are allowed" allow
# Control character in a path and in a tool name block with the input message, not a crash.
mk_json '{tool_name:"Write",tool_input:{file_path:($p+"/notes/a\u001bb"),content:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G48f ESC inside file_path" block "bad tool input (path field)"
mk_json '{tool_name:"Write",tool_input:{file_path:($p+"/notes/a\u007fb"),content:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G48f DEL inside file_path" block "bad tool input (path field)"
mk_json '{tool_name:"Wr\u0001ite",tool_input:{file_path:($p+"/notes/a"),content:"x"},cwd:"/nowhere"}'
run_gate $lim "$tmp/in.json"; expect "T-G48f U+0001 inside tool_name" block "bad tool input (tool_name)"

# ---- T-G40: timing on a large contract (the hook timeout is 10 s).
echo "# timing, ${BIG_KB:-500} KB contract"
hb="$proj/docs/contracts/huge.md"
{
  printf -- '---\nstatus: draft\nowner: dave\n---\n# Huge\n'
  awk -v kb="${BIG_KB:-500}" 'BEGIN { max = kb * 1024; for (i = 1; sz < max; i++) {
      l = sprintf("Line %d: the agent reads the contract, checks the invariant, and reports the result.%s\n", i, (i % 50 == 0 ? " repeat-token" : ""))
      printf "%s", l; sz += length(l)
      if (i == 2500) printf "UNIQUE-HUGE-MARKER\n" } }'
} > "$hb"
echo "INFO: huge.md is $(wc -c < "$hb" | tr -d ' ') bytes"
mk_edit docs/contracts/huge.md "UNIQUE-HUGE-MARKER" "UNIQUE-HUGE-MARKER edited"
run_gate 10 "$tmp/in.json"; timed "T-G40a Edit on huge contract" 5; [ "$hung" -eq 1 ] || expect "T-G40a result" allow
mk_edit docs/contracts/huge.md "repeat-token" "repeat-word" true
run_gate 10 "$tmp/in.json"; timed "T-G40b Edit replace_all on huge contract" 5; [ "$hung" -eq 1 ] || expect "T-G40b result" allow
mk_edit docs/contracts/huge.md "repeat-token" "repeat-word" '"true"'
run_gate 10 "$tmp/in.json"; timed "T-G40c Edit replace_all as a string on huge contract" 5; [ "$hung" -eq 1 ] || expect "T-G40c result" allow
mk_write docs/contracts/huge.md "$hb"
run_gate 10 "$tmp/in.json"; timed "T-G40d Write on huge contract" 5; [ "$hung" -eq 1 ] || expect "T-G40d result" allow
mk_edit docs/contracts/huge.md "status: draft" "status: approved"
run_gate 10 "$tmp/in.json"; timed "T-G40e Edit draft to approved on huge contract" 5; [ "$hung" -eq 1 ] || expect "T-G40e result" block "Only Dave approves"
# Escape-dense: every line has \u, \x and curly quotes, the worst case for the loose reading.
he="$proj/docs/contracts/huge-esc.md"
{
  printf -- '---\nstatus: draft\nowner: dave\n---\n# Huge, escapes\n'
  awk -v kb="${BIG_KB:-500}" 'BEGIN { max = kb * 1024; for (i = 1; sz < max; i++) {
      l = sprintf("Line %d: \\u0061 \\x61 \342\200\234quoted\342\200\235 status: approved-ish text. repeat-token\n", i)
      printf "%s", l; sz += length(l)
      if (i == 2500) printf "UNIQUE-ESC-MARKER\n" } }'
} > "$he"
echo "INFO: huge-esc.md is $(wc -c < "$he" | tr -d ' ') bytes, $(grep -c 'u0061' "$he") lines with escapes"
mk_edit docs/contracts/huge-esc.md "UNIQUE-ESC-MARKER" "UNIQUE-ESC-MARKER edited"
run_gate 10 "$tmp/in.json"; timed "T-G40f Edit on escape-dense huge contract" 5; [ "$hung" -eq 1 ] || expect "T-G40f result" allow
mk_edit docs/contracts/huge-esc.md "repeat-token" "repeat-word" '"true"'
run_gate 10 "$tmp/in.json"; timed "T-G40g Edit replace_all as a string on escape-dense huge contract" 5; [ "$hung" -eq 1 ] || expect "T-G40g result" allow
mk_write docs/contracts/huge-esc.md "$he"
run_gate 10 "$tmp/in.json"; timed "T-G40h Write on escape-dense huge contract" 5; [ "$hung" -eq 1 ] || expect "T-G40h result" allow
# Near the limit: a ${BIG2_KB:-1024} KB escape-dense contract (about 9 times the largest real contract, 118 KB) must finish in
# 6 s, well inside the hook timeout of 10 s. The hook grows faster than linearly: 2048 KB takes about 8.6 s on jq 1.8.2 and 21 s on jq 1.6.
hh="$proj/docs/contracts/huge2.md"
{
  printf -- '---\nstatus: draft\nowner: dave\n---\n# Huge 2\n'
  awk -v kb="${BIG2_KB:-1024}" 'BEGIN { max = kb * 1024; for (i = 1; sz < max; i++) {
      l = sprintf("Line %d: \\u0061 \\x61 \342\200\234quoted\342\200\235 status: approved-ish text. repeat-token\n", i)
      printf "%s", l; sz += length(l)
      if (i == 9000) printf "UNIQUE-HUGE2-MARKER\n" } }'
} > "$hh"
echo "INFO: huge2.md is $(wc -c < "$hh" | tr -d ' ') bytes"
mk_edit docs/contracts/huge2.md "UNIQUE-HUGE2-MARKER" "UNIQUE-HUGE2-MARKER edited"
run_gate 10 "$tmp/in.json"; timed "T-G40i Edit on a ${BIG2_KB:-1024} KB escape-dense contract" 6; [ "$hung" -eq 1 ] || expect "T-G40i result" allow
mk_edit docs/contracts/huge2.md "repeat-token" "repeat-word" '"true"'
run_gate 10 "$tmp/in.json"; timed "T-G40j Edit replace_all as a string on a ${BIG2_KB:-1024} KB contract" 6; [ "$hung" -eq 1 ] || expect "T-G40j result" allow
mk_write docs/contracts/huge2.md "$hh"
run_gate 10 "$tmp/in.json"; timed "T-G40k Write on a ${BIG2_KB:-1024} KB contract" 6; [ "$hung" -eq 1 ] || expect "T-G40k result" allow
mk_edit docs/contracts/huge2.md "status: draft" "status: approved"
run_gate 10 "$tmp/in.json"; timed "T-G40l Edit draft to approved on a ${BIG2_KB:-1024} KB contract" 6; [ "$hung" -eq 1 ] || expect "T-G40l result" block "Only Dave approves"
sed 's/^status: draft/status: approved/' "$hh" > "$proj/docs/contracts/huge3.md"
mk_edit docs/contracts/huge3.md "UNIQUE-HUGE2-MARKER" "UNIQUE-HUGE2-MARKER edited"
run_gate 10 "$tmp/in.json"; timed "T-G40m Edit on an approved ${BIG2_KB:-1024} KB contract" 6; [ "$hung" -eq 1 ] || expect "T-G40m result" block "is approved. Set status: draft"
fi

# ---- The hook only reads: the repo state must be unchanged
after="$(git_state)"
if [ "$before" = "$after" ]; then ok "repo unchanged (status, git diff, untracked file hashes)"; else bad "repo changed during the run (status, diff, or untracked file content)"; fi

echo "Summary: $pass ok, $fail fail, $gap known gap, $skipped skipped"
if [ "$skipped" -gt 0 ]; then
  echo "Skipped cases:$skiplist"
  if [ "${ALLOW_SKIP:-}" != 1 ]; then
    echo "FAIL: $skipped case(s) were skipped. Fix the environment, or set ALLOW_SKIP=1 to accept the skip list above."
    exit 1
  fi
  echo "ALLOW_SKIP=1: the skip list above is accepted."
fi
[ "$fail" -eq 0 ]
