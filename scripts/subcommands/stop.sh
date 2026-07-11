#!/usr/bin/env bash
# subcommand: stop — stop keycloak.service (ADR-0005).
# shellcheck shell=bash

cmd_stop() {
  [[ $# -eq 0 ]] || {
    log_error "stop takes no arguments"
    return "$EX_USAGE"
  }
  sd_action stop
}
