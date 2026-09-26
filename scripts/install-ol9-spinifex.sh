#!/usr/bin/env bash
# Fully automated Oracle Linux 9 Spinifex installation and service start.
# Contributed by Johan Louwers. This is a thin, auditable wrapper around the
# production setup.sh: it validates the OL9-only safety contract, then leaves
# users, packages, units, and firewall setup to the single supported installer.
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    exec sudo -E "$0" "$@"
fi

# shellcheck disable=SC1091
. /etc/os-release
if [[ ${ID:-} != ol || ${VERSION_ID%%.*} != 9 ]]; then
    echo "This helper supports Oracle Linux 9 only (found ${ID:-unknown} ${VERSION_ID:-unknown})." >&2
    exit 2
fi

: "${SPINIFEX_OL9_NETWORK_REPO_URL:?set the HTTPS signed network RPM repository URL}"
: "${SPINIFEX_OL9_NETWORK_REPO_GPGKEY_URL:?set the HTTPS repository GPG key URL}"

case "$SPINIFEX_OL9_NETWORK_REPO_URL,$SPINIFEX_OL9_NETWORK_REPO_GPGKEY_URL" in
    https://*,https://*) ;;
    *) echo "OL9 network repository and GPG key URLs must use HTTPS." >&2; exit 2 ;;
esac

SPINIFEX_RELEASE_REPOSITORY="${INSTALL_SPINIFEX_GITHUB_REPOSITORY:-mulgadc/spinifex}"
SPINIFEX_RELEASE_REF="${INSTALL_SPINIFEX_VERSION:-main}"
SPINIFEX_INSTALLER_URL="${SPINIFEX_INSTALLER_URL:-https://raw.githubusercontent.com/${SPINIFEX_RELEASE_REPOSITORY}/${SPINIFEX_RELEASE_REF}/scripts/setup.sh}"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
installer="$tmpdir/setup.sh"

curl --fail --silent --show-error --location "$SPINIFEX_INSTALLER_URL" --output "$installer"
chmod 0700 "$installer"

# setup.sh consumes INSTALL_SPINIFEX_* and SPINIFEX_OL9_NETWORK_REPO_* directly.
# It installs the selected release, writes systemd units, and starts the target.
bash "$installer"
systemctl enable --now spinifex.target
systemctl is-active --quiet spinifex.target
systemctl --no-pager --full status spinifex.target

echo "Spinifex installation and spinifex.target startup completed on Oracle Linux 9."
