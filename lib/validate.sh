#!/usr/bin/env bash
# lib/validate.sh — shared pass/fail reporting for check/verify/health.
# shellcheck shell=bash

# validate_reset — zero the counters (call once at the start of a run).
validate_reset() {
  VLD_PASS=0
  VLD_FAIL=0
  VLD_WARN=0
  VLD_SKIP=0
}

# validate_item <PASS|FAIL|WARN|SKIP> <label> [detail]
validate_item() {
  local status="$1" label="$2" detail="${3:-}"
  printf '[%-4s] %-9s %s\n' "$status" "$label" "$detail"
  case "$status" in
    PASS) VLD_PASS=$((VLD_PASS + 1)) ;;
    FAIL) VLD_FAIL=$((VLD_FAIL + 1)) ;;
    WARN) VLD_WARN=$((VLD_WARN + 1)) ;;
    SKIP) VLD_SKIP=$((VLD_SKIP + 1)) ;;
  esac
}

# validate_summary — print totals; return EX_CONFIG if any FAIL.
validate_summary() {
  printf 'checks: %d passed, %d failed, %d warnings, %d skipped\n' \
    "$VLD_PASS" "$VLD_FAIL" "$VLD_WARN" "$VLD_SKIP"
  [[ "$VLD_FAIL" -eq 0 ]] || return "$EX_CONFIG"
}
