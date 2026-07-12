#!/usr/bin/env bats
# Smoke test for the dispatcher + version subcommand.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCIMAGE="$REPO_ROOT/scripts/kcimage"
}

@test "kcimage version prints KIB version from VERSION file" {
  run "$KCIMAGE" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"kcimage (KIB)"* ]]
  [[ "$output" == *"keycloak baseline: 26.x"* ]]
}

@test "kcimage --help exits 0 and lists commands" {
  run "$KCIMAGE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"install"* ]]
  [[ "$output" == *"seal"* ]]
}

@test "unknown command reports unimplemented" {
  run "$KCIMAGE" no-such-command
  [ "$status" -ne 0 ]
}
