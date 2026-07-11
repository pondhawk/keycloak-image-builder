#!/usr/bin/env bash
# subcommand: journal — systemd journal for both Keycloak units (boot + service).
# Useful for diagnosing first-boot configuration (ADR-0005).
# shellcheck shell=bash

cmd_journal() {
  case "${1:-}" in
    -h | --help)
      echo "Usage: kcadmin journal [journalctl-args...]"
      echo "Shows keycloak.service + keycloak-config.service journal."
      return 0
      ;;
  esac
  sd_journal --no-pager "$@"
}
