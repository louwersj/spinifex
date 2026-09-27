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
# A fresh OL9 node normally has one uplink, often the same interface used for
# SSH. NAT mode is therefore the only safe unattended default: it never moves
# that uplink into OVS. Operators with a dedicated physical WAN can opt out and
# run setup-ovn manually with their explicit bridge arguments.
INSTALL_SPINIFEX_OL9_AUTO_INITIALIZE="${INSTALL_SPINIFEX_OL9_AUTO_INITIALIZE:-1}"
INSTALL_SPINIFEX_OL9_NODE="${INSTALL_SPINIFEX_OL9_NODE:-node1}"
INSTALL_SPINIFEX_OL9_NODES="${INSTALL_SPINIFEX_OL9_NODES:-1}"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
installer="$tmpdir/setup.sh"

curl --fail --silent --show-error --location "$SPINIFEX_INSTALLER_URL" --output "$installer"
chmod 0700 "$installer"

# setup.sh consumes INSTALL_SPINIFEX_* directly. Its usual interactive
# `newgrp spinifex` convenience shell would stop this one-command wrapper
# before networking and initialization, so explicitly skip it here. Service
# accounts and all normal setup work are still created by setup.sh.
INSTALL_SPINIFEX_SKIP_NEWGRP=1 bash "$installer"
if [[ "$INSTALL_SPINIFEX_OL9_AUTO_INITIALIZE" == 1 ]]; then
    echo "[INFO] Configuring safe single-node OVN NAT networking"
    /usr/local/share/spinifex/setup-ovn.sh --management --nat-uplink
    echo "[INFO] Initializing single-node Spinifex"
    # sudo on EL9 commonly uses secure_path without /usr/local/bin. The
    # installer places spx there, so use its canonical absolute path instead
    # of depending on the invoking user's interactive PATH.
    /usr/local/bin/spx admin init --node "$INSTALL_SPINIFEX_OL9_NODE" --nodes "$INSTALL_SPINIFEX_OL9_NODES" --external-mode=nat
elif [[ "$INSTALL_SPINIFEX_OL9_AUTO_INITIALIZE" != 0 ]]; then
    echo "INSTALL_SPINIFEX_OL9_AUTO_INITIALIZE must be 0 or 1" >&2
    exit 2
fi
systemctl enable --now spinifex.target
systemctl is-active --quiet spinifex.target
# A systemd target with Wants= dependencies becomes active even if a wanted
# service fails. OVS is the non-negotiable OL9 datapath prerequisite, so make
# the public helper fail here instead of printing a misleading success message.
systemctl is-active --quiet openvswitch.service
systemctl --no-pager --full status spinifex.target

echo "Spinifex installation, OVS datapath validation, and spinifex.target startup completed on Oracle Linux 9."
