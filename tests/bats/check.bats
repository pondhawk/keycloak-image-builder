#!/usr/bin/env bats
# check subcommand — read-only; assert structure, not host-dependent pass/fail.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCADMIN="$REPO_ROOT/scripts/kcadmin"
}

@test "check --help exits 0" {
  run "$KCADMIN" check --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"prerequisite checks"* ]]
}

@test "check reports all expected items and a summary" {
  run "$KCADMIN" check
  [[ "$output" == *"Java"* ]]
  [[ "$output" == *"systemd"* ]]
  [[ "$output" == *"SELinux"* ]]
  [[ "$output" == *"DNS"* ]]
  [[ "$output" == *"checks:"* ]]
}

@test "check skips RDS when no db host given" {
  run "$KCADMIN" check
  [[ "$output" == *"[SKIP"*"RDS"* ]]
}

@test "check rejects unknown args" {
  run "$KCADMIN" check --bogus
  [ "$status" -ne 0 ]
}
