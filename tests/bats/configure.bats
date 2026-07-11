#!/usr/bin/env bats
# configure subcommand — render into a temp --etc-dir (no root needed).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCADMIN="$REPO_ROOT/scripts/kcadmin"
  ETC="$BATS_TEST_TMPDIR/etc"
}

@test "configure --help exits 0" {
  run "$KCADMIN" configure --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Render config from templates"* ]]
}

@test "configure with no target errors" {
  run "$KCADMIN" configure
  [ "$status" -ne 0 ]
  [[ "$output" == *"nothing to do"* ]]
}

@test "configure renders keycloak.conf with mysql vendor" {
  run "$KCADMIN" configure --db-vendor mysql --etc-dir "$ETC"
  [ "$status" -eq 0 ]
  [ -f "$ETC/keycloak.conf" ]
  grep -q '^db=mysql$' "$ETC/keycloak.conf"
}

@test "configure renders keycloak.conf with postgres vendor" {
  run "$KCADMIN" configure --db-vendor postgres --etc-dir "$ETC"
  [ "$status" -eq 0 ]
  grep -q '^db=postgres$' "$ETC/keycloak.conf"
}

@test "configure rejects an invalid vendor" {
  run "$KCADMIN" configure --db-vendor oracle --etc-dir "$ETC"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --db-vendor"* ]]
}

@test "rendered keycloak.conf has no endpoint or secret in its directives" {
  run "$KCADMIN" configure --db-vendor mysql --etc-dir "$ETC"
  [ "$status" -eq 0 ]
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$ETC/keycloak.conf' | grep -iE 'password|secret|://|amazonaws'"
  [ "$status" -ne 0 ]
}

@test "dry-run configure writes nothing" {
  run "$KCADMIN" --dry-run configure --db-vendor mysql --etc-dir "$ETC"
  [ "$status" -eq 0 ]
  [ ! -f "$ETC/keycloak.conf" ]
}

@test "configure --env renders keycloak.env from the environment" {
  export KC_DB_URL="jdbc:mysql://db.example:3306/keycloak"
  export KC_HOSTNAME="https://auth.example.com"
  run "$KCADMIN" configure --env --etc-dir "$ETC"
  [ "$status" -eq 0 ]
  grep -q "KC_DB_URL=jdbc:mysql://db.example:3306/keycloak" "$ETC/keycloak.env"
  grep -q "KC_HOSTNAME=https://auth.example.com" "$ETC/keycloak.env"
}

@test "configure --env fails when required env is missing" {
  run env -u KC_DB_URL -u KC_HOSTNAME "$KCADMIN" configure --env --etc-dir "$ETC"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required env"* ]]
}
