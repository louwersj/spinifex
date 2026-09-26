#!/usr/bin/env bash
# Fully automated Oracle Linux 9 Spinifex installation and service start.
# Contributed by Johan Louwers. This is a thin, auditable wrapper around the
# production setup.sh: it validates the OL9-only architecture contract, then
# leaves users, Oracle-signed packages, units, and firewall setup to the single
# supported installer. It needs no private RPM repository, EPEL, or Ansible.
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

if [[ $(uname -m) != x86_64 ]]; then
    echo "Oracle's OVS/OVN oVirt repository is currently published only for x86_64." >&2
    exit 2
fi

# Be deliberately strict rather than silently honouring old private-repository
# variables. The supported path is fully reproducible from Oracle's signed RPM
# repositories, which is important for installations from either a fork or the
# upstream project.
if [[ ${SPINIFEX_OL9_NETWORK_SOURCE:-oracle} != oracle ]]; then
    echo "SPINIFEX_OL9_NETWORK_SOURCE must be 'oracle'." >&2
    exit 2
fi

SPINIFEX_RELEASE_REPOSITORY="${INSTALL_SPINIFEX_GITHUB_REPOSITORY:-mulgadc/spinifex}"
SPINIFEX_RELEASE_REF="${INSTALL_SPINIFEX_VERSION:-main}"
SPINIFEX_INSTALLER_URL="${SPINIFEX_INSTALLER_URL:-https://raw.githubusercontent.com/${SPINIFEX_RELEASE_REPOSITORY}/${SPINIFEX_RELEASE_REF}/scripts/setup.sh}"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
installer="$tmpdir/setup.sh"

curl --fail --silent --show-error --location "$SPINIFEX_INSTALLER_URL" --output "$installer"
chmod 0700 "$installer"

# setup.sh consumes INSTALL_SPINIFEX_* directly. It installs the selected
# release, enables the Oracle oVirt RPM repositories, writes compatibility
# units, and starts the target.
bash "$installer"
systemctl enable --now spinifex.target
systemctl is-active --quiet spinifex.target
# A systemd target with Wants= dependencies becomes active even if a wanted
# service fails. OVS is the non-negotiable OL9 datapath prerequisite, so make
# the public helper fail here instead of printing a misleading success message.
systemctl is-active --quiet openvswitch.service
systemctl --no-pager --full status spinifex.target

echo "Spinifex installation, OVS datapath validation, and spinifex.target startup completed on Oracle Linux 9."
