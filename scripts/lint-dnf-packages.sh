#!/usr/bin/env bash
# Oracle Linux 9 DNF validation contributed by Johan Louwers.
# Resolve the Oracle Linux 9 *base* dependency list against the supported DNF
# repositories. The OVS/OVN runtime comes from an explicitly configured,
# signed Spinifex repository and is verified by the VM release test; Oracle
# does not publish a production-supported equivalent. See
# docs/install/oracle-linux-9/README.md.
set -euo pipefail

IMAGE="${1:-oraclelinux:9}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

INSTALL_SPINIFEX_LIB_ONLY=1
export INSTALL_SPINIFEX_LIB_ONLY
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/setup.sh"

if [ -z "${OL9_BASE_RUNTIME_PACKAGES:-}" ]; then
    echo "setup.sh did not define OL9_BASE_RUNTIME_PACKAGES" >&2
    exit 1
fi

echo "Resolving ${IMAGE}..."
docker run --rm -e "PACKAGES=qemu-kvm ${OL9_BASE_RUNTIME_PACKAGES}" "${IMAGE}" bash -ceu '
    dnf install -y --setopt=install_weak_deps=False $PACKAGES >/dev/null
'

echo "OK: every Oracle Linux 9 base runtime package resolves"
