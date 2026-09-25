#!/usr/bin/env bash
# Fast host-platform regression checks. Package availability is checked in
# containers by lint-apt-packages.sh and lint-dnf-packages.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

run_case() {
    local name="$1" release="$2" expected="$3"
    printf '%s\n' "$release" >"$TMPDIR/os-release"
    if ! out=$(INSTALL_SPINIFEX_LIB_ONLY=1 OS_RELEASE_FILE="$TMPDIR/os-release" \
        bash -c 'uname() { echo x86_64; }; . "$1/setup.sh"; detect_os; detect_arch; printf "%s:%s:%s" "$PLATFORM_FAMILY" "$ARCH" "$QEMU_PACKAGES"' _ "$SCRIPT_DIR" 2>&1); then
        echo "FAIL: $name: detect_os failed: $out" >&2
        exit 1
    fi
    case "$out" in
        *"$expected") ;;
        *) echo "FAIL: $name: wanted $expected, got: $out" >&2; exit 1 ;;
    esac
}

run_case debian $'ID=debian\nVERSION_ID=13\nPRETTY_NAME="Debian 13"' 'debian:amd64:qemu-system-x86'
run_case ubuntu $'ID=ubuntu\nVERSION_ID=24.04\nPRETTY_NAME="Ubuntu 24.04"' 'debian:amd64:qemu-system-x86'
run_case ol9 $'ID=ol\nVERSION_ID=9.6\nPRETTY_NAME="Oracle Linux Server 9.6"' 'ol9:amd64:qemu-kvm'

repo_contract_case() {
    local name="$1" expected="$2"
    shift 2
    if out=$(env INSTALL_SPINIFEX_LIB_ONLY=1 "$@" \
        bash -c '. "$1/setup.sh"; configure_ol9_network_repo' _ "$SCRIPT_DIR" 2>&1); then
        echo "FAIL: $name: repository configuration unexpectedly succeeded" >&2
        exit 1
    fi
    case "$out" in
        *"$expected"*) ;;
        *) echo "FAIL: $name: wanted $expected, got: $out" >&2; exit 1 ;;
    esac
}

repo_contract_case ol9-repo-url SPINIFEX_OL9_NETWORK_REPO_URL
repo_contract_case ol9-repo-key SPINIFEX_OL9_NETWORK_REPO_GPGKEY_URL \
    SPINIFEX_OL9_NETWORK_REPO_URL=https://packages.example.invalid/ol9/x86_64

echo "OK: platform selection and Oracle Linux 9 signed-repository contract"
