#!/usr/bin/env bash
# Resolve the Oracle Linux 9 runtime dependency list against the real DNF
# repositories. Mirrors lint-apt-packages.sh so packaging regressions fail in
# CI before a release reaches an OL9 host.
set -euo pipefail

IMAGE="${1:-oraclelinux:9}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

INSTALL_SPINIFEX_LIB_ONLY=1
export INSTALL_SPINIFEX_LIB_ONLY
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/setup.sh"

if [ -z "${OL9_RUNTIME_PACKAGES:-}" ]; then
    echo "setup.sh did not define OL9_RUNTIME_PACKAGES" >&2
    exit 1
fi

echo "Resolving ${IMAGE}..."
docker run --rm -e "PACKAGES=qemu-kvm ${OL9_RUNTIME_PACKAGES}" "${IMAGE}" bash -ceu '
    dnf install -y --setopt=install_weak_deps=False $PACKAGES >/dev/null
'

echo "OK: every Oracle Linux 9 runtime package resolves"
