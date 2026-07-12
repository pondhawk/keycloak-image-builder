#!/usr/bin/env bats
# clean — dry-run + arg/guard validation (never a real removal of system paths).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCIMAGE="$REPO_ROOT/scripts/kcimage"
}

@test "clean --help exits 0" {
  run "$KCIMAGE" clean --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"return"*"pristine"* || "$output" == *"Remove the KIB install"* ]]
}

@test "clean rejects unknown args" {
  run "$KCIMAGE" clean --bogus
  [ "$status" -ne 0 ]
}

@test "a real clean without --yes (or root) fails" {
  run "$KCIMAGE" clean
  [ "$status" -ne 0 ]
}

@test "dry-run clean reports state and changes nothing" {
  run "$KCIMAGE" --dry-run clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
  [ ! -e /opt/keycloak ]
}
