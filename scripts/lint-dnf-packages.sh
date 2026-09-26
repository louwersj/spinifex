#!/usr/bin/env bash
# Oracle Linux 9 DNF validation contributed by Johan Louwers.
# Resolve the complete Oracle Linux 9 dependency list against the exact
# Oracle-signed repositories used by the installer. This deliberately does
# not enable EPEL: Oracle's openvswitch2.17-ipsec package requires LibreSwan,
# and installing EPEL StrongSwan would conflict over `/usr/sbin/ipsec`.
# See docs/install/oracle-linux-9/README.md.
set -euo pipefail

IMAGE="${1:-oraclelinux:9}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

INSTALL_SPINIFEX_LIB_ONLY=1
export INSTALL_SPINIFEX_LIB_ONLY
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/setup.sh"

if [ -z "${OL9_BASE_RUNTIME_PACKAGES:-}" ] || [ -z "${OL9_NETWORK_RUNTIME_PACKAGES:-}" ]; then
    echo "setup.sh did not define the complete Oracle Linux 9 package contract" >&2
    exit 1
fi

echo "Resolving ${IMAGE}..."
# `--platform` makes an Apple Silicon development machine test the x86_64
# deployment target. GitHub's x86_64 runners use the same image natively.
docker run --rm --platform "${DOCKER_PLATFORM:-linux/amd64}" \
    -e "PACKAGES=qemu-kvm ${OL9_BASE_RUNTIME_PACKAGES} ${OL9_NETWORK_RUNTIME_PACKAGES}" \
    "${IMAGE}" bash -ceu '
    # Match setup.sh exactly: point DNF at the public Oracle oVirt repositories
    # and its already-installed Oracle signing key. This avoids the UEK kernel
    # dependency carried by the general-purpose oracle-ovirt-release RPM.
    cat >/etc/yum.repos.d/spinifex-oracle-ovirt45.repo <<EOF
[spinifex-oracle-ovirt-4.5]
name=Oracle Linux 9 oVirt 4.5 for Spinifex (\$basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/ovirt45/\$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
enabled=1
gpgcheck=1

[spinifex-oracle-ovirt-4.5-extra]
name=Oracle Linux 9 oVirt 4.5 Extra for Spinifex (\$basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/ovirt45/extras/\$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
enabled=1
gpgcheck=1
EOF
    dnf install -y --setopt=install_weak_deps=False $PACKAGES >/dev/null
'

echo "OK: every Oracle Linux 9 runtime package resolves from Oracle repositories"
