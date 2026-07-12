#!/usr/bin/env bash
# boot/configure-node.sh — ExecStart of keycloak-config.service (ADR-0005/0008).
# Baked into the AMI; runs once at boot as root, before keycloak.service.
#
# Flow (single JSON secret per cluster, ADR-0008):
#   1. read KDT_SECRET_ID (the cluster secret's name) from launch-template user-data
#   2. read this node's private IP from IMDSv2
#   3. fetch the one cluster secret from Secrets Manager (instance IAM role)
#   4. split it — non-secret fields -> /etc/keycloak/keycloak.env
#                 secret fields     -> /run/keycloak/secrets.env (tmpfs)
#
# SKELETON: steps 1-3 (user-data + IMDS + Secrets Manager) are the Secrets work;
# the env render (step 4) is real and self-contained.
#
# Requires (model-instance prerequisites, baked into the AMI — see README):
#   - AWS CLI v2 (official bundle; not in the RHEL repos)
#   - jq (from dnf: `dnf install jq`)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETC="/etc/keycloak"
RUN="/run/keycloak"

# The env template sits beside this script when installed, or under ../templates
# when run from the repo/tarball.
TEMPLATE=""
for cand in "$SCRIPT_DIR/keycloak.env" "$SCRIPT_DIR/../templates/keycloak.env"; do
  [[ -f "$cand" ]] && {
    TEMPLATE="$cand"
    break
  }
done
[[ -n "$TEMPLATE" ]] || {
  echo "keycloak-config: keycloak.env template not found" >&2
  exit 1
}

install -d -m 0750 "$ETC"
install -d -m 0750 -o root -g keycloak "$RUN"

# 1. TODO(boot): read the cluster secret name from user-data, and this node's
#    private IP from IMDSv2, e.g.:
#      KDT_SECRET_ID=$(...from user-data...)
#      tok=$(curl -sX PUT .../api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
#      export NODE_PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $tok" .../local-ipv4)
#
# 2. TODO(secrets, ADR-0008): fetch the ONE cluster secret and unpack its fields:
#      json=$(aws secretsmanager get-secret-value --secret-id "$KDT_SECRET_ID" \
#               --query SecretString --output text)
#      export KC_DB_URL=$(jq -r .db_url <<<"$json")
#      export KC_HOSTNAME=$(jq -r .hostname <<<"$json")
#      export JAVA_OPTS_APPEND=$(jq -r .java_opts_append <<<"$json")
#      # secret fields -> tmpfs (0640 root:keycloak); bootstrap_admin_* only when
#      # the DB is uninitialized:
#      umask 027
#      { printf 'KC_DB_USERNAME=%s\n' "$(jq -r .db_username <<<"$json")"
#        printf 'KC_DB_PASSWORD=%s\n' "$(jq -r .db_password <<<"$json")"; } > "$RUN/secrets.env"

# 3. Render the non-secret runtime env file (real; only the intended vars).
# shellcheck disable=SC2016  # ${VARS} are envsubst's argument, not shell expansion
envsubst '${KC_DB_URL} ${KC_HOSTNAME} ${NODE_PRIVATE_IP} ${JAVA_OPTS_APPEND}' \
  < "$TEMPLATE" > "$ETC/keycloak.env"
chmod 0640 "$ETC/keycloak.env"

echo "keycloak-config: node configuration complete"
