#!/usr/bin/env bash
# subcommand: logs — application logs for keycloak.service (ADR-0005/0010).
# shellcheck shell=bash

cmd_logs() {
  local jargs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f | --follow)
        jargs+=(-f)
        shift
        ;;
      -n)
        jargs+=(-n "${2:-}")
        shift 2
        ;;
      --since)
        jargs+=(--since "${2:-}")
        shift 2
        ;;
      -h | --help)
        echo "Usage: kcadmin logs [-f|--follow] [-n LINES] [--since WHEN]"
        return 0
        ;;
      *)
        log_error "logs: unknown argument: $1"
        return "$EX_USAGE"
        ;;
    esac
  done
  sd_logs --no-pager "${jargs[@]}"
}
