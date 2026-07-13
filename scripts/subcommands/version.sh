#!/usr/bin/env bash
# subcommand: version — print KIB and baseline versions.
# shellcheck shell=bash

cmd_version() {
  printf 'kcimage (KIB) %s\n' "$(kib_version)"
  printf 'keycloak baseline: %s.x\n' "$KIB_KEYCLOAK_BASELINE"
  printf 'java: OpenJDK %s\n' "$KIB_JAVA_MAJOR"
  printf 'arch: %s\n' "$(kib_arch_label "$(kib_arch || uname -m)")"
}
