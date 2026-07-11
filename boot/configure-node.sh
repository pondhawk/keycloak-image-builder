#!/usr/bin/env bash
# boot/configure-node.sh — ExecStart of keycloak-config.service (ADR-0005/0008).
# Baked into the AMI; runs once at boot as root, before keycloak.service:
# prepare tmpfs, fetch secrets, resolve instance facts, render the runtime env.
#
# SKELETON: secret retrieval and IMDS lookups are completed in the Secrets work;
# the env render below is real (self-contained, no kcadmin dependency).
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/keycloak.env"
ETC="/etc/keycloak"

install -d -m 0750 -o root -g keycloak /run/keycloak

# 1. TODO(secrets, ADR-0008): fetch DB credentials (and bootstrap admin if the
#    DB is uninitialized) from AWS Secrets Manager via the instance role +
#    IMDSv2, then write them to /run/keycloak/secrets.env (0640 root:keycloak).

# 2. TODO(boot): resolve NODE_PRIVATE_IP from IMDSv2 and export KC_DB_URL /
#    KC_HOSTNAME from launch-template user-data.

# 3. Render the runtime environment file (real; only the intended vars).
install -d -m 0750 "$ETC"
# shellcheck disable=SC2016  # ${VARS} are envsubst's argument, not shell expansion
envsubst '${KC_DB_URL} ${KC_HOSTNAME} ${NODE_PRIVATE_IP} ${JAVA_OPTS_APPEND}' \
  < "$TEMPLATE" > "$ETC/keycloak.env"
chmod 0640 "$ETC/keycloak.env"

echo "keycloak-config: node configuration complete"
