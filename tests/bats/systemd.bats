#!/usr/bin/env bats
# service lifecycle commands — dry-run for mutating actions (no real systemctl).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCADMIN="$REPO_ROOT/scripts/kcadmin"
}

@test "dry-run start plans systemctl start keycloak.service" {
  run "$KCADMIN" --dry-run start
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] systemctl start keycloak.service"* ]]
}

@test "dry-run stop plans systemctl stop keycloak.service" {
  run "$KCADMIN" --dry-run stop
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] systemctl stop keycloak.service"* ]]
}

@test "dry-run restart plans systemctl restart keycloak.service" {
  run "$KCADMIN" --dry-run restart
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] systemctl restart keycloak.service"* ]]
}

@test "start rejects arguments" {
  run "$KCADMIN" --dry-run start now
  [ "$status" -ne 0 ]
  [[ "$output" == *"takes no arguments"* ]]
}

@test "logs --help exits 0" {
  run "$KCADMIN" logs --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: kcadmin logs"* ]]
}

@test "logs rejects unknown args" {
  run "$KCADMIN" logs --bogus
  [ "$status" -ne 0 ]
}

@test "journal --help exits 0" {
  run "$KCADMIN" journal --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: kcadmin journal"* ]]
}
