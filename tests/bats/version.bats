#!/usr/bin/env bats
# Smoke test for the dispatcher + version subcommand.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCADMIN="$REPO_ROOT/scripts/kcadmin"
}

@test "kcadmin version prints KDT version from VERSION file" {
  run "$KCADMIN" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"kcadmin (KDT)"* ]]
  [[ "$output" == *"keycloak baseline: 26.x"* ]]
}

@test "kcadmin --help exits 0 and lists commands" {
  run "$KCADMIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"install"* ]]
  [[ "$output" == *"ami-clean"* ]]
}

@test "unknown command reports unimplemented" {
  run "$KCADMIN" no-such-command
  [ "$status" -ne 0 ]
}
