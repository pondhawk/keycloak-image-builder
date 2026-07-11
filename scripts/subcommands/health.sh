#!/usr/bin/env bash
# subcommand: health — probe the node-local health endpoints (ADR-0006 Level 1).
# Hostname-independent: hits the management port directly. Not a Keycloak test —
# just confirms KDT's node is up and DB-connected (ADR-0012).
# shellcheck shell=bash

_health_usage() {
  cat << EOF
Usage: kcadmin health [--host <h>] [--management-port <p>]

Probe /health/live and /health/ready on the management port.

  --host <h>              Host to probe (default: localhost)
  --management-port <p>   Management port (default: 9000)
  -h, --help              Show this help
EOF
}

_health_probe() {
  local url="$1" label="$2"
  if curl -fsS -m 5 "$url" > /dev/null 2>&1; then
    validate_item PASS "$label" "$url"
  else
    validate_item FAIL "$label" "unreachable: $url"
  fi
}

cmd_health() {
  local host="localhost" mport="9000"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        host="${2:-}"
        shift 2
        ;;
      --management-port)
        mport="${2:-}"
        shift 2
        ;;
      -h | --help)
        _health_usage
        return 0
        ;;
      *)
        log_error "health: unknown argument: $1"
        _health_usage
        return "$EX_USAGE"
        ;;
    esac
  done

  require_cmd curl || return "$EX_CONFIG"
  validate_reset
  _health_probe "http://$host:$mport/health/live" live
  _health_probe "http://$host:$mport/health/ready" ready
  validate_summary
}
