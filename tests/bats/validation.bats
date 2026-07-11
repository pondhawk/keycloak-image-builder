#!/usr/bin/env bats
# build / health / verify — dry-run and structure (no real server/build needed).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  KCADMIN="$REPO_ROOT/scripts/kcadmin"
}

# --- build ---

@test "build --help exits 0" {
  run "$KCADMIN" build --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Build (augment)"* ]]
}

@test "dry-run build plans kc.sh build" {
  run "$KCADMIN" --dry-run build
  [ "$status" -eq 0 ]
  [[ "$output" == *"kc.sh build"* ]]
  [[ "$output" == *"KC_CONFIG_FILE=/etc/keycloak/keycloak.conf"* ]]
}

@test "build rejects unknown args" {
  run "$KCADMIN" build --bogus
  [ "$status" -ne 0 ]
}

# --- health ---

@test "health --help exits 0" {
  run "$KCADMIN" health --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"health/live"* ]]
}

@test "health probes live and ready" {
  run "$KCADMIN" health --management-port 59999
  [[ "$output" == *"live"* ]]
  [[ "$output" == *"ready"* ]]
  [[ "$output" == *"checks:"* ]]
}

# --- verify ---

@test "verify --help exits 0" {
  run "$KCADMIN" verify --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Validate that KDT provisioned"* ]]
}

@test "verify reports all items and a summary" {
  run "$KCADMIN" verify
  [[ "$output" == *"Java"* ]]
  [[ "$output" == *"install"* ]]
  [[ "$output" == *"config"* ]]
  [[ "$output" == *"SELinux"* ]]
  [[ "$output" == *"units"* ]]
  [[ "$output" == *"checks:"* ]]
}

@test "verify passes config with a rendered keycloak.conf" {
  local etc="$BATS_TEST_TMPDIR/etc"
  mkdir -p "$etc"
  printf 'db=mysql\n' > "$etc/keycloak.conf"
  run "$KCADMIN" verify --etc-dir "$etc"
  [[ "$output" == *"[PASS] config"* ]]
}

@test "verify passes units when unit files are present" {
  local sd="$BATS_TEST_TMPDIR/sd"
  mkdir -p "$sd"
  touch "$sd/keycloak.service" "$sd/keycloak-config.service"
  run "$KCADMIN" verify --systemd-dir "$sd"
  [[ "$output" == *"[PASS] units"* ]]
}
