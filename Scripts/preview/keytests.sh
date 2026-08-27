#!/bin/zsh
# Keyboard-navigation verification.
#
# There is no XCTest target (build.sh is raw swiftc), so each case drives the
# real chain — NSEvent monitor, guards, view model, render — inside the preview
# harness and asserts on the resulting state.
#
# Usage: ./Scripts/preview/keytests.sh
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$ROOT/build/preview.log"
PASS=0; FAIL=0; RETRIED=0

attempt() {
  local keys="$1" extra="$2"
  ( export CALBAR_CLEAR=1 CALBAR_KEYS="$keys"; eval "$extra"; \
    "$ROOT/Scripts/preview/shoot.sh" "$ROOT/build/kt.png" ) >/dev/null 2>&1
  grep -m1 '^keys=' "$LOG" 2>/dev/null
}

# run <name> <keys> <env-assignments> <expected-substring>
#
# Retries once. This drives a real GUI through synthetic events, so a case can
# occasionally lose a keystroke to window activation timing — verified as a
# harness artifact, not a product bug, by re-running failures by hand. A retry
# that passes is reported as such rather than silently, so genuine flakiness
# stays visible instead of being smoothed away.
run() {
  local name="$1" keys="$2" extra="$3" expect="$4"
  local got
  got=$(attempt "$keys" "$extra")
  if [[ "$got" == *"$expect"* ]]; then
    print -r -- "  PASS  $name"; ((PASS++)); return
  fi
  local first="$got"
  got=$(attempt "$keys" "$extra")
  if [[ "$got" == *"$expect"* ]]; then
    print -r -- "  PASS  $name  (after retry \u2014 first run: ${first:-<no report>})"
    ((PASS++)); ((RETRIED++))
  else
    print -r -- "  FAIL  $name"
    print -r -- "        expected to contain: $expect"
    print -r -- "        got:                 ${got:-<no report line>}"
    ((FAIL++))
  fi
}

print -r -- "Keyboard navigation (today = 27 Aug 2026)"
run "right moves one day"            "right"                       ""                    "selected=2026-08-28"
run "right x2"                       "right,right"                 ""                    "selected=2026-08-29"
run "left moves back"                "left"                        ""                    "selected=2026-08-26"
run "down moves a week"              "down"                        ""                    "selected=2026-09-03"
run "up moves back a week"           "up"                          ""                    "selected=2026-08-20"
run "down x2 is two weeks"           "down,down"                   ""                    "selected=2026-09-10"
run "forward past month end flips"   "right,right,right,right,right" ""                  "selected=2026-09-01 month=2026-09-01"
run "back past month start flips"    "left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left,left" "" "selected=2026-07-31 month=2026-07-01"
run "cmd-right next month"           "cmd-right"                   ""                    "month=2026-09-01"
run "cmd-left previous month"        "cmd-left"                    ""                    "month=2026-07-01"
run "cmd-t returns to today"         "cmd-right,cmd-right,cmd-t"   ""                    "selected=2026-08-27 month=2026-08-01"
run "leap day is not skipped"        "right"                       "export CALBAR_SELECT=550" "selected=2028-02-29"
run "week start Sun behaves same"    "right"                       "export CALBAR_WEEKSTART=sun" "selected=2026-08-28"

print -r -- "Focus and dismissal"
run "return focuses the field"       "return,right"                ""                    "selected=2026-08-27"
run "esc leaves field, keeps panel"  "return,esc"                  ""                    "shown=true"
run "esc closes go-to-date"          "esc"                         "export CALBAR_GOTO=1" "goto=false shown=true"
run "esc closes the panel"           "esc"                         ""                    "shown=false"

print -r -- ""
if (( RETRIED > 0 )); then
  print -r -- "$PASS passed, $FAIL failed  ($RETRIED needed a retry)"
else
  print -r -- "$PASS passed, $FAIL failed"
fi
[[ $FAIL -eq 0 ]]
