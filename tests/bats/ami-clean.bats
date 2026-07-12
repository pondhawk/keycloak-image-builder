#!/usr/bin/env bats
# ami-clean — dry-run planning + the neutrality gate (--check, safe to run).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCADMIN="$REPO_ROOT/scripts/kcadmin"
  ETC="$BATS_TEST_TMPDIR/etc"
  mkdir -p "$ETC"
}

@test "ami-clean --help exits 0" {
  run "$KCADMIN" ami-clean --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sanitize this instance"* ]]
}

@test "dry-run ami-clean plans sanitization and changes nothing" {
  run "$KCADMIN" --dry-run ami-clean --etc-dir "$ETC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
}

@test "ami-clean prunes non-current Keycloak versions" {
  local opt="$BATS_TEST_TMPDIR/opt"
  mkdir -p "$opt/keycloak-26.1.4" "$opt/keycloak-26.2.0"
  ln -s keycloak-26.2.0 "$opt/current"
  run "$KCADMIN" --dry-run ami-clean --etc-dir "$ETC" --opt-dir "$opt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove old install: $opt/keycloak-26.1.4"* ]]
  [[ "$output" != *"remove old install: $opt/keycloak-26.2.0"* ]]
}

@test "gate passes on a neutral config dir" {
  printf 'db=mysql\n' > "$ETC/keycloak.conf"
  run "$KCADMIN" ami-clean --check --etc-dir "$ETC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gate passed"* ]]
}

@test "gate fails when keycloak.env is present" {
  printf 'db=mysql\n' > "$ETC/keycloak.conf"
  touch "$ETC/keycloak.env"
  run "$KCADMIN" ami-clean --check --etc-dir "$ETC"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive file still present"* ]]
}

@test "gate fails when a secret pattern is present" {
  printf 'db-password=hunter2\n' > "$ETC/keycloak.conf"
  run "$KCADMIN" ami-clean --check --etc-dir "$ETC"
  [ "$status" -ne 0 ]
  [[ "$output" == *"possible secret/endpoint"* ]]
}
