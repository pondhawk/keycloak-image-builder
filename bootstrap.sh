#!/usr/bin/env bash
# bootstrap.sh — install the Keycloak Image Builder toolkit (kcimage) onto this
# host, so you run `kcimage` from PATH (never a versioned path).
# Run once per toolkit version:  sudo ./bootstrap.sh
# Re-run after downloading a newer release to upgrade in place.
set -Eeuo pipefail

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
BINDIR="$PREFIX/bin"
LIBDIR="$PREFIX/lib/kcimage"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

install -d "$DESTDIR$LIBDIR"/lib "$DESTDIR$LIBDIR"/subcommands \
  "$DESTDIR$LIBDIR"/templates "$DESTDIR$LIBDIR"/boot "$DESTDIR$LIBDIR"/selinux \
  "$DESTDIR$LIBDIR"/systemd
install -m 0644 lib/*.sh "$DESTDIR$LIBDIR/lib/"
install -m 0644 scripts/subcommands/*.sh "$DESTDIR$LIBDIR/subcommands/"
install -m 0644 templates/* "$DESTDIR$LIBDIR/templates/"
install -m 0755 boot/*.sh "$DESTDIR$LIBDIR/boot/"
install -m 0644 selinux/* "$DESTDIR$LIBDIR/selinux/"
install -m 0644 systemd/*.service "$DESTDIR$LIBDIR/systemd/"
install -m 0644 VERSION "$DESTDIR$LIBDIR/VERSION"

install -d "$DESTDIR$BINDIR"
install -m 0755 scripts/kcimage "$DESTDIR$BINDIR/kcimage"

# Also expose kcimage on sudo's secure_path. /usr/sbin is in the default (and
# most hardened) secure_path; /usr/local/bin often is not, which makes
# `sudo kcimage` fail with "command not found". A symlink here fixes that
# without editing sudoers (which would override a deliberate hardening choice).
SBINDIR="/usr/sbin"
install -d "$DESTDIR$SBINDIR"
ln -sfn "$BINDIR/kcimage" "$DESTDIR$SBINDIR/kcimage"

# Create the operator's custom-providers folder in their home (real installs
# only; works under sudo, where $HOME would be root's).
if [[ -z "$DESTDIR" ]]; then
  user="${SUDO_USER:-${USER:-root}}"
  uhome="$(getent passwd "$user" 2> /dev/null | cut -d: -f6)"
  [[ -n "$uhome" ]] || uhome="${HOME:-/root}"
  install -d "$uhome/keycloak-custom-providers"
  chown "$user:" "$uhome/keycloak-custom-providers" 2> /dev/null || true
  echo "custom providers: put JARs in $uhome/keycloak-custom-providers"
fi

echo "installed kcimage $(cat VERSION) to $DESTDIR$BINDIR/kcimage"
echo "  (also symlinked at $DESTDIR$SBINDIR/kcimage so 'sudo kcimage' works)"
