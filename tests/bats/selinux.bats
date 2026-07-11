#!/usr/bin/env bats
# selinux subcommand — dry-run planning (no semanage/root required).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCADMIN="$REPO_ROOT/scripts/kcadmin"
  FC="$REPO_ROOT/selinux/keycloak.fc"
}

@test "selinux --help exits 0" {
  run "$KCADMIN" selinux --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"kcadmin selinux apply"* ]]
}

@test "selinux with no action errors" {
  run "$KCADMIN" selinux
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing action"* ]]
}

@test "dry-run selinux apply plans fcontext labels" {
  run "$KCADMIN" --dry-run selinux apply --fc "$FC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would label /opt/keycloak(/.*)? as usr_t"* ]]
  [[ "$output" == *"as etc_t"* ]]
}

@test "selinux apply with a missing fc file errors" {
  run "$KCADMIN" --dry-run selinux apply --fc /nonexistent.fc
  [ "$status" -ne 0 ]
  [[ "$output" == *"fcontext file not found"* ]]
}

@test "selinux unknown action errors" {
  run "$KCADMIN" selinux frobnicate
  [ "$status" -ne 0 ]
}
