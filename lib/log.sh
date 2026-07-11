#!/usr/bin/env bash
# lib/log.sh — logging helpers. Sourced, never executed. Never log secrets (ADR-0008).
# shellcheck shell=bash

# Logs go to stderr so command stdout stays clean for data return.
_log() {
  local level="$1"; shift
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*" >&2
}

log_info() { _log INFO "$@"; }
log_warn() { _log WARN "$@"; }
log_error() { _log ERROR "$@"; }
log_debug() { [[ "${VERBOSE:-0}" == "1" ]] && _log DEBUG "$@"; return 0; }
