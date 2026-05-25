#!/usr/bin/env bash
# Tiny assertion helpers used by tests/unit.sh and tests/smoke.sh.
# Pure bash; no external runners (bats/etc.) required.

set -euo pipefail

# --- output ------------------------------------------------------------------
_green='\033[0;32m'
_red='\033[0;31m'
_yellow='\033[0;33m'
_dim='\033[2m'
_reset='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '  %bok%b %s\n' "$_green" "$_reset" "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '  %bFAIL%b %s\n' "$_red" "$_reset" "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
warn() { printf '  %bwarn%b %s\n' "$_yellow" "$_reset" "$1"; }
step() { printf '\n==> %s\n' "$1"; }

summary() {
  echo
  if [[ $FAIL_COUNT -eq 0 ]]; then
    printf '%bAll %d checks passed.%b\n' "$_green" "$PASS_COUNT" "$_reset"
    return 0
  fi
  printf '%b%d passed, %d failed.%b\n' "$_red" "$PASS_COUNT" "$FAIL_COUNT" "$_reset"
  return 1
}

# --- assertions --------------------------------------------------------------

# assert_cmd "<label>" <cmd...>  — passes if cmd exits 0
assert_cmd() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label (cmd: $*)"
  fi
}

# assert_http "<label>" <url> [<expect_status>=200]
assert_http() {
  local label="$1" url="$2" expect="${3:-200}"
  local got
  got=$(curl -fsS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "ERR")
  if [[ "$got" == "$expect" ]]; then
    pass "$label ($url → $got)"
  else
    fail "$label ($url expected $expect, got $got)"
  fi
}

# wait_http <url> <timeout_s> "<label>"
# polls until 200 OK or timeout
wait_http() {
  local url="$1" timeout="$2" label="$3"
  local deadline=$(( SECONDS + timeout ))
  while (( SECONDS < deadline )); do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
      pass "$label ready ($url)"
      return 0
    fi
    sleep 2
  done
  fail "$label not ready after ${timeout}s ($url)"
  return 1
}

# assert_contains "<label>" "<haystack>" "<needle>"
assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label (missing: '$needle')"
  fi
}
