#!/usr/bin/env bash
# subcommand: start — start keycloak.service (ADR-0005).
# shellcheck shell=bash

cmd_start() {
  [[ $# -eq 0 ]] || {
    log_error "start takes no arguments"
    return "$EX_USAGE"
  }
  sd_action start
}
