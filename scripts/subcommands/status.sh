#!/usr/bin/env bash
# subcommand: status — show keycloak.service status (ADR-0005).
# shellcheck shell=bash

cmd_status() {
  [[ $# -eq 0 ]] || {
    log_error "status takes no arguments"
    return "$EX_USAGE"
  }
  sd_status
}
