#!/usr/bin/env bash
# Runs contract-gate-test.sh for every bash and jq found, and says what it could not run.
# The hook is registered for bash 3.2 (macOS) and runs on bash 5 (Linux CI) with jq 1.6 to 1.8.
# Usage: contract-gate-matrix.sh
#   GATE            hook under test (passed through; default is the repo hook)
#   MATRIX_BASHES   space-separated bash binaries (default: /bin/bash and every bash found in common places)
#   MATRIX_JQS      space-separated jq binaries (default: every jq found in common places)
#   ALLOW_SKIP=1    a missing bash 3, bash 4+, jq 1.6, jq 1.7 or jq 1.8 is reported but does not fail the run
# Each combination is one full run of contract-gate-test.sh. Nothing is skipped silently:
# every combination that was not run prints "NOT RUN", and the run fails unless ALLOW_SKIP=1.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
suite="$here/contract-gate-test.sh"
[ -f "$suite" ] || { echo "FAIL: $suite not found"; exit 1; }

uniq_bin() { # print each executable once, by path
  local b seen=" "
  for b in "$@"; do
    [ -x "$b" ] || continue
    case "$seen" in *" $b "*) continue ;; esac
    seen="$seen$b "; echo "$b"
  done
}
bashes="${MATRIX_BASHES:-$(uniq_bin /bin/bash /usr/bin/bash /opt/homebrew/bin/bash /usr/local/bin/bash "$(command -v bash)")}"
jqs="${MATRIX_JQS:-$(uniq_bin /usr/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq /opt/anaconda3/bin/jq "$(command -v jq)")}"

bash_major() { "$1" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null; }
jq_minor() { # jq-1.7.1-apple -> 1.7
  "$1" --version 2>/dev/null | sed -E 's/^jq-([0-9]+)\.([0-9]+).*/\1.\2/'
}

ran=0; failed=0; seen_bash=" "; seen_jq=" "
for b in $bashes; do
  bm="$(bash_major "$b")"; [ -n "$bm" ] || { echo "NOT RUN: $b is not a working bash"; continue; }
  for j in $jqs; do
    jm="$(jq_minor "$j")"; [ -n "$jm" ] || { echo "NOT RUN: $j is not a working jq"; continue; }
    echo "=== bash $bm ($b) x jq $jm ($j)"
    if GATE_BASH="$b" JQ="$j" bash "$suite"; then echo "=== PASS bash $bm x jq $jm"
    else echo "=== FAIL bash $bm x jq $jm"; failed=$((failed + 1)); fi
    ran=$((ran + 1))
    case "$bm" in 3) seen_bash="${seen_bash}3 " ;; *) seen_bash="${seen_bash}4+ " ;; esac
    seen_jq="${seen_jq}${jm} "
  done
done

missing=0
for need in 3 4+; do
  case "$seen_bash" in *" $need "*) ;; *) echo "NOT RUN: no bash $need was found (set MATRIX_BASHES)"; missing=$((missing + 1)) ;; esac
done
for need in 1.6 1.7 1.8; do
  case "$seen_jq" in *" $need "*) ;; *) echo "NOT RUN: no jq $need was found (set MATRIX_JQS)"; missing=$((missing + 1)) ;; esac
done
echo "Matrix: $ran run(s), $failed failed, $missing required version(s) not run"
[ "$failed" -eq 0 ] || exit 1
if [ "$missing" -gt 0 ] && [ "${ALLOW_SKIP:-}" != 1 ]; then echo "FAIL: set ALLOW_SKIP=1 to accept the NOT RUN list above"; exit 1; fi
[ "$ran" -gt 0 ]
