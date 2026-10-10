#!/usr/bin/env bash
# Tests for dset, dpush and install.sh. Uses stubs for doppler, pbpaste and pbcopy: no real secrets, no network.
# Run: bash tests/test_scripts.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }
expect() { # expect "description" <command...>
  local desc="$1"
  shift
  if "$@"; then ok; else bad "$desc"; fi
}
contains() { [[ "$1" == *"$2"* ]]; }
not_contains() { [[ "$1" != *"$2"* ]]; }
file_is() { [[ -f "$1" && "$(cat "$1")" == "$2" ]]; }
file_absent() { [[ ! -e "$1" ]]; }
file_empty() { [[ -f "$1" && ! -s "$1" ]]; }
perms_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

setup() {
  TMP="$(mktemp -d)"
  export STUB_STORE="$TMP/stub"
  mkdir -p "$STUB_STORE" "$TMP/home"
  export HOME="$TMP/home"
  export PATH="$ROOT/tests/stubs:$ROOT/bin:$PATH"
  export SECRET_HANDOFF_CONFIG="$TMP/config"
  printf 'DEPOT_PROJECT=depot\nDEPOT_CONFIG=stg\n' > "$SECRET_HANDOFF_CONFIG"
  unset DEPOT_PROJECT DEPOT_CONFIG STUB_CORRUPT
  : > "$STUB_STORE/clipboard"
}
clip() { printf '%s' "$1" > "$STUB_STORE/clipboard"; }
store() { echo "$STUB_STORE/store/$1"; }
run() { OUT="$("$@" 2>&1)"; RC=$?; }

VAL="dummy-value-7f3a"

# --- dset: happy path ---
setup
clip "$VAL"
run dset TEST_A
expect "dset exits 0" test "$RC" -eq 0
expect "dset stores the value" file_is "$(store depot__stg__TEST_A)" "$VAL"
expect "dset clears the clipboard" file_empty "$STUB_STORE/clipboard"
expect "dset reports new" contains "$OUT" "new in depot/stg"
expect "dset output has no value" not_contains "$OUT" "$VAL"
expect "doppler argv has no value" not_contains "$(cat "$STUB_STORE/argv.log")" "$VAL"

# --- dset: update ---
clip "another-value-91"
run dset TEST_A
expect "dset reports updated" contains "$OUT" "updated in depot/stg"
expect "dset overwrites the value" file_is "$(store depot__stg__TEST_A)" "another-value-91"

# --- dset: trailing newline in the clipboard ---
setup
printf 'abc\n\n' > "$STUB_STORE/clipboard"
run dset TEST_NL
expect "trailing newlines are stripped" file_is "$(store depot__stg__TEST_NL)" "abc"

# --- dset: refusals ---
setup
run dset TEST_EMPTY
expect "empty clipboard exits 1" test "$RC" -eq 1
expect "empty clipboard stores nothing" file_absent "$(store depot__stg__TEST_EMPTY)"
clip "$VAL"
run dset lower_case
expect "lowercase name exits 1" test "$RC" -eq 1
run dset
expect "no argument exits 1" test "$RC" -eq 1
run dset TEST_A --project other --config prd
expect "extra arguments exit 1" test "$RC" -eq 1
expect "refusals keep the clipboard" file_is "$STUB_STORE/clipboard" "$VAL"

# --- dset: verification failure keeps the clipboard ---
setup
clip "$VAL"
STUB_CORRUPT=1 run dset TEST_BAD
expect "corrupt store exits 1" test "$RC" -eq 1
expect "corrupt store keeps the clipboard" file_is "$STUB_STORE/clipboard" "$VAL"
expect "corrupt store message has no value" not_contains "$OUT" "$VAL"
expect "corrupt store reports a difference" contains "$OUT" "differs"

# --- config handling ---
setup
rm -f "$SECRET_HANDOFF_CONFIG"
clip "$VAL"
run dset TEST_A
expect "missing config exits 1" test "$RC" -eq 1
expect "missing config points to setup" contains "$OUT" "setup"

setup
clip "$VAL"
DEPOT_PROJECT=envproj DEPOT_CONFIG=envcfg run dset TEST_A
expect "environment overrides the config" file_is "$(store envproj__envcfg__TEST_A)" "$VAL"

setup
printf 'DEPOT_PROJECT=depot; touch %s/pwned\nDEPOT_CONFIG=stg\n' "$TMP" > "$SECRET_HANDOFF_CONFIG"
clip "$VAL"
run dset TEST_A
expect "config with shell syntax is rejected" test "$RC" -eq 1
expect "config is never executed" file_absent "$TMP/pwned"

# --- dpush ---
setup
clip "$VAL"
run dset TEST_P
run dpush TEST_P app prd
expect "dpush exits 0" test "$RC" -eq 0
expect "dpush copies the value" file_is "$(store app__prd__TEST_P)" "$VAL"
expect "dpush keeps the depot copy" file_is "$(store depot__stg__TEST_P)" "$VAL"
expect "dpush output has no value" not_contains "$OUT" "$VAL"
expect "doppler argv has no value after dpush" not_contains "$(cat "$STUB_STORE/argv.log")" "$VAL"
run dpush TEST_P app dev
expect "dpush to a second target works" file_is "$(store app__dev__TEST_P)" "$VAL"

run dpush TEST_MISSING app prd
expect "dpush without source exits 1" test "$RC" -eq 1
expect "dpush without source suggests dset" contains "$OUT" "dset TEST_MISSING"
run dpush TEST_P depot stg
expect "dpush to the depot exits 1" test "$RC" -eq 1
run dpush TEST_P App prd
expect "dpush with uppercase project exits 1" test "$RC" -eq 1
run dpush TEST_P app
expect "dpush with missing config exits 1" test "$RC" -eq 1
STUB_CORRUPT=1 run dpush TEST_P app qa
expect "dpush with corrupt target exits 1" test "$RC" -eq 1
expect "dpush corrupt message has no value" not_contains "$OUT" "$VAL"

# --- xtrace must not leak the value ---
setup
clip "$VAL"
OUT="$(bash -x "$ROOT/bin/dset" TEST_X 2>&1)"
RC=$?
expect "dset works under bash -x" test "$RC" -eq 0
expect "dset under bash -x does not leak the value" not_contains "$OUT" "$VAL"
OUT="$(bash -x "$ROOT/bin/dpush" TEST_X app prd 2>&1)"
RC=$?
expect "dpush works under bash -x" test "$RC" -eq 0
expect "dpush under bash -x does not leak the value" not_contains "$OUT" "$VAL"

# --- install.sh ---
setup
BIN="$TMP/bin"
CFG="$TMP/inst/config"
OUT="$(PREFIX="$BIN" SECRET_HANDOFF_CONFIG="$CFG" bash "$ROOT/install.sh" myproj dev 2>&1)"
RC=$?
expect "install exits 0" test "$RC" -eq 0
expect "install writes the config" file_is "$CFG" $'DEPOT_PROJECT=myproj\nDEPOT_CONFIG=dev'
expect "config is private (600)" test "$(perms_of "$CFG")" = "600"
expect "dset is executable" test -x "$BIN/dset"
expect "dpush is executable" test -x "$BIN/dpush"
expect "library is installed" test -f "$BIN/handoff-lib.sh"
clip "$VAL"
OUT="$(PATH="$BIN:$ROOT/tests/stubs:/usr/bin:/bin" SECRET_HANDOFF_CONFIG="$CFG" "$BIN/dset" INST_TEST 2>&1)"
RC=$?
expect "installed dset works" test "$RC" -eq 0
expect "installed dset uses the written depot" file_is "$(store myproj__dev__INST_TEST)" "$VAL"

OUT="$(PREFIX="$BIN" SECRET_HANDOFF_CONFIG="$CFG" bash "$ROOT/install.sh" "Bad Project" dev 2>&1)"
RC=$?
expect "install rejects invalid slugs" test "$RC" -eq 1
OUT="$(PREFIX="$BIN" SECRET_HANDOFF_CONFIG="$CFG" bash "$ROOT/install.sh" onlyone 2>&1)"
RC=$?
expect "install rejects missing arguments" test "$RC" -eq 1

echo "scripts: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
