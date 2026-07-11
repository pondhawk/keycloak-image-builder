#!/usr/bin/env bash
# boot/configure-node.sh — ExecStart of keycloak-config.service (ADR-0005/0008).
# Runs once at boot as root, before keycloak.service: prepare tmpfs, fetch
# secrets, resolve instance facts, render the runtime env, validate.
#
# SKELETON: secret retrieval and IMDS lookups are completed in the Secrets
# milestone; the env-render step is already real (kcadmin configure --env).
set -Eeuo pipefail

RUN_DIR="/run/keycloak"
install -d -m 0750 -o root -g keycloak "$RUN_DIR"

# 1. TODO(secrets, ADR-0008): fetch DB credentials (and, if uninitialized, the
#    bootstrap admin) from AWS Secrets Manager via the instance role + IMDSv2,
#    then write them to "$RUN_DIR/secrets.env" (0640 root:keycloak).

# 2. TODO(boot): resolve this node's private IP from IMDSv2 into NODE_PRIVATE_IP,
#    and export KC_DB_URL / KC_HOSTNAME from launch-template user-data.

# 3. Render the runtime environment file from the process environment (real).
kcadmin configure --env

# 4. TODO(validate): confirm required runtime config is present before the
#    server is allowed to start (fail non-zero to block keycloak.service).

echo "keycloak-config: node configuration complete"
