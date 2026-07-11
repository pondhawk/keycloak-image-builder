#!/usr/bin/env bats
# install subcommand — only dry-run / validation paths (never a real install,
# so it is safe under any CI user, including root).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCADMIN="$REPO_ROOT/scripts/kcadmin"
}

@test "install requires --keycloak-version" {
  run "$KCADMIN" install
  [ "$status" -ne 0 ]
  [[ "$output" == *"--keycloak-version is required"* ]]
}

@test "install rejects an invalid version" {
  run "$KCADMIN" install --keycloak-version "not.a.version!"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --keycloak-version"* ]]
}

@test "install --help exits 0" {
  run "$KCADMIN" install --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Lay down OpenJDK"* ]]
}

@test "dry-run install performs no mutating action and completes" {
  run "$KCADMIN" --dry-run install --keycloak-version 26.1.4
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"install complete"* ]]
}

@test "dry-run install does not download or create the target dir" {
  run "$KCADMIN" --dry-run install --keycloak-version 26.1.4
  [ "$status" -eq 0 ]
  [ ! -e /opt/keycloak/keycloak-26.1.4 ]
}
