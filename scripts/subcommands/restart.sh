#!/usr/bin/env bash
# subcommand: restart — restart keycloak.service (ADR-0005).
# shellcheck shell=bash

cmd_restart() {
  [[ $# -eq 0 ]] || {
    log_error "restart takes no arguments"
    return "$EX_USAGE"
  }
  sd_action restart
}
