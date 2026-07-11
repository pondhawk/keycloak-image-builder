#!/usr/bin/env bash
# subcommand: verify — golden-image / node validation (ADR-0012 pre-clean gate).
# SKELETON: checks are implemented in the Validation milestone (§19 M7).
# shellcheck shell=bash

cmd_verify() {
  log_info "kcadmin verify — validating that KDT did its job (not testing Keycloak)"
  # Planned checks (ADR-0012 §2 "before ami-clean"):
  #   - java present and major == KDT_JAVA_MAJOR
  #   - kc.sh build succeeded; 'start --optimized' works
  #   - /health/ready and /health/live pass
  #   - SELinux Enforcing; expected fcontexts present
  #   - systemd units valid; config rendered from templates
  log_warn "verify checks not yet implemented (planned: Validation milestone)"
  return "$EX_UNIMPLEMENTED"
}
