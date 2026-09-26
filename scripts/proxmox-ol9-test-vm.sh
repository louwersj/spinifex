#!/usr/bin/env bash
# Create or destroy a disposable Oracle Linux 9 VM for local Spinifex testing.
# Contributed by Johan Louwers: documents and reproduces the tested Proxmox
# hardware contract (host CPU, VirtIO root disk, standard VGA) explicitly.
#
# This intentionally targets a single-node Proxmox test environment.  It uses
# the host CPU model and a VirtIO root disk: the Oracle OL9 KVM image did not
# boot reliably with Proxmox's default CPU/SCSI combination in our test lab.
set -euo pipefail

ACTION="${1:-create}"
PVE_ENV_FILE="${PVE_ENV_FILE:-$HOME/.config/spinifex/proxmox.env}"

if [[ ! -r "$PVE_ENV_FILE" ]]; then
    echo "PVE_ENV_FILE is not readable: $PVE_ENV_FILE" >&2
    exit 2
fi

set -a
# shellcheck disable=SC1090
source "$PVE_ENV_FILE"
set +a

: "${PVE_API_URL:?set PVE_API_URL in $PVE_ENV_FILE}"
: "${PVE_API_TOKEN_ID:?set PVE_API_TOKEN_ID in $PVE_ENV_FILE}"
: "${PVE_API_TOKEN_SECRET:?set PVE_API_TOKEN_SECRET in $PVE_ENV_FILE}"

PVE_NODE="${PVE_NODE:-proxmox0}"
PVE_POOL="${PVE_POOL:-spinifex-ci}"
PVE_VM_ID="${PVE_VM_ID:-106}"
PVE_VM_NAME="${PVE_VM_NAME:-spinifex-ol9-test}"
PVE_DISK_STORAGE="${PVE_DISK_STORAGE:-local-lvm}"
PVE_ISO_STORAGE="${PVE_ISO_STORAGE:-local}"
PVE_BRIDGE="${PVE_BRIDGE:-vmbr0}"
PVE_OL9_IMAGE_VOLID="${PVE_OL9_IMAGE_VOLID:-local:import/OL9U5_x86_64-kvm-b259.qcow2}"
PVE_ROOT_PASSWORD="${PVE_ROOT_PASSWORD:-}"
# Disabled by default. Setting this to 1 is only for local automation where
# the test runner must SSH with the expiring root password; never use it for a
# production or Internet-reachable Spinifex host.
PVE_ENABLE_ROOT_SSH_PASSWORD_LOGIN="${PVE_ENABLE_ROOT_SSH_PASSWORD_LOGIN:-0}"
PVE_SSH_PUBLIC_KEY_FILE="${PVE_SSH_PUBLIC_KEY_FILE:-}"
PVE_CPU_CORES="${PVE_CPU_CORES:-2}"
PVE_MEMORY_MIB="${PVE_MEMORY_MIB:-2048}"

api() {
    local method="$1" path="$2"
    shift 2
    curl --fail --silent --show-error --insecure --request "$method" \
        --header "Authorization: PVEAPIToken=${PVE_API_TOKEN_ID}=${PVE_API_TOKEN_SECRET}" \
        "$@" "${PVE_API_URL}${path}"
}

wait_task() {
    local task="$1" state exitstatus
    for _ in $(seq 1 120); do
        state=$(api GET "/nodes/${PVE_NODE}/tasks/${task}/status" | jq -r '.data.status')
        exitstatus=$(api GET "/nodes/${PVE_NODE}/tasks/${task}/status" | jq -r '.data.exitstatus // ""')
        if [[ "$state" == stopped ]]; then
            [[ "$exitstatus" == OK ]] || { echo "Proxmox task failed: $exitstatus" >&2; return 1; }
            return 0
        fi
        sleep 2
    done
    echo "Timed out waiting for Proxmox task: $task" >&2
    return 1
}

vm_exists() {
    api GET '/cluster/resources?type=vm' | jq -e --argjson vmid "$PVE_VM_ID" \
        '.data[] | select(.vmid == $vmid)' >/dev/null
}

make_seed_iso() {
    local tmpdir="$1" seed_dir="$tmpdir/cidata" ssh_key="" ssh_password_auth=false password_expiry=true
    case "$PVE_ENABLE_ROOT_SSH_PASSWORD_LOGIN" in
        0) ;;
        # Automated guest testing needs a password that does not force an
        # interactive change on first SSH login. This exception is constrained
        # to an explicitly named local disposable-test switch; all default
        # console-only VMs retain the safer first-login expiry behavior.
        1) ssh_password_auth=true; password_expiry=false ;;
        *) echo "PVE_ENABLE_ROOT_SSH_PASSWORD_LOGIN must be 0 or 1" >&2; return 2 ;;
    esac
    mkdir -p "$seed_dir"
    if [[ -n "$PVE_SSH_PUBLIC_KEY_FILE" ]]; then
        ssh_key=$(tr -d '\n' <"$PVE_SSH_PUBLIC_KEY_FILE")
    fi
    cat >"$seed_dir/meta-data" <<EOF
instance-id: spinifex-ol9-${PVE_VM_ID}
local-hostname: ${PVE_VM_NAME}
EOF
    cat >"$seed_dir/user-data" <<EOF
#cloud-config
hostname: ${PVE_VM_NAME}
manage_etc_hosts: true
disable_root: false
ssh_pwauth: ${ssh_password_auth}
chpasswd:
  expire: ${password_expiry}
  users:
    - {name: root, password: '${PVE_ROOT_PASSWORD}', type: text}
EOF
    if [[ -n "$ssh_key" ]]; then
        printf 'ssh_authorized_keys:\n  - %s\n' "$ssh_key" >>"$seed_dir/user-data"
    fi
    cat >>"$seed_dir/user-data" <<'EOF'
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF
    if [[ "$PVE_ENABLE_ROOT_SSH_PASSWORD_LOGIN" == 1 ]]; then
        cat >>"$seed_dir/user-data" <<EOF
  # Local-test-only: permit the short disposable root password so the test
  # runner can execute the same installer an end user receives. A dedicated
  # early drop-in wins over later cloud-image defaults. Repeat chpasswd here:
  # this both documents the deliberate test credential and avoids a cloud-init
  # image variation silently skipping the declarative chpasswd stanza above.
  - install -d -m 0755 /etc/ssh/sshd_config.d
  - printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/00-spinifex-local-test.conf
  - printf '%s\n' 'root:${PVE_ROOT_PASSWORD}' | chpasswd
  - systemctl restart sshd
EOF
    fi

    if command -v xorriso >/dev/null; then
        xorriso -as mkisofs -o "$tmpdir/seed.iso" -V cidata -J -R "$seed_dir" >/dev/null 2>&1
    elif command -v genisoimage >/dev/null; then
        genisoimage -output "$tmpdir/seed.iso" -volid cidata -joliet -rock "$seed_dir" >/dev/null
    elif command -v hdiutil >/dev/null; then
        hdiutil makehybrid -iso -joliet -default-volume-name cidata -o "$tmpdir/seed.iso" "$seed_dir" >/dev/null
    else
        echo "Need xorriso, genisoimage, or hdiutil to create the NoCloud ISO" >&2
        return 1
    fi
}

create_vm() {
    [[ -n "$PVE_ROOT_PASSWORD" ]] || { echo "Set PVE_ROOT_PASSWORD (it is never printed or stored in the repo)." >&2; exit 2; }
    # This is intentionally a disposable test credential. Keep it short at the
    # request of the local test operator; cloud-init expires it after first use
    # by default. PVE_ENABLE_ROOT_SSH_PASSWORD_LOGIN=1 is the explicit local
    # automation exception and must never be used beyond this isolated test VM.
    [[ "$PVE_ROOT_PASSWORD" =~ ^[A-Za-z0-9@%+=.,:_-]{1,8}$ ]] || {
        echo "PVE_ROOT_PASSWORD must be 1-8 characters from A-Za-z0-9@%+=.,:_-" >&2; exit 2;
    }
    vm_exists && { echo "Refusing to replace existing VM ${PVE_VM_ID}; run '$0 destroy' explicitly first." >&2; exit 1; }

    local tmpdir seed_name task response
    tmpdir=$(mktemp -d)
    trap 'rm -rf "${tmpdir:-}"' EXIT
    make_seed_iso "$tmpdir"
    seed_name="spinifex-ol9-vm-${PVE_VM_ID}-$(date +%s)-seed.iso"
    response=$(api POST "/nodes/${PVE_NODE}/storage/${PVE_ISO_STORAGE}/upload" \
        --form 'content=iso' --form "filename=@${tmpdir}/seed.iso;filename=${seed_name}")
    task=$(jq -r '.data' <<<"$response")
    wait_task "$task"

    response=$(api POST "/nodes/${PVE_NODE}/qemu" \
        --data-urlencode "vmid=${PVE_VM_ID}" \
        --data-urlencode "name=${PVE_VM_NAME}" \
        --data-urlencode "pool=${PVE_POOL}" \
        --data-urlencode "cores=${PVE_CPU_CORES}" \
        --data-urlencode "memory=${PVE_MEMORY_MIB}" \
        --data-urlencode 'balloon=1024' --data-urlencode 'cpu=host' --data-urlencode 'ostype=l26' \
        --data-urlencode "virtio0=${PVE_DISK_STORAGE}:0,import-from=${PVE_OL9_IMAGE_VOLID}" \
        --data-urlencode "ide2=${PVE_ISO_STORAGE}:iso/${seed_name},media=cdrom" \
        --data-urlencode "net0=virtio,bridge=${PVE_BRIDGE}" --data-urlencode 'agent=1' \
        --data-urlencode 'serial0=socket' --data-urlencode 'vga=std' --data-urlencode 'boot=order=virtio0' \
        --data-urlencode 'onboot=0' --data-urlencode 'tags=spinifex-ci;oraclelinux9;test')
    task=$(jq -r '.data' <<<"$response")
    wait_task "$task"
    response=$(api POST "/nodes/${PVE_NODE}/qemu/${PVE_VM_ID}/status/start")
    wait_task "$(jq -r '.data' <<<"$response")"
    if [[ "$PVE_ENABLE_ROOT_SSH_PASSWORD_LOGIN" == 1 ]]; then
        echo "VM ${PVE_VM_ID} is running. Local-test root password SSH is enabled without first-login expiry."
    else
        echo "VM ${PVE_VM_ID} is running. Root password is set to expire on first successful login."
    fi
}

destroy_vm() {
    vm_exists || { echo "VM ${PVE_VM_ID} does not exist."; return 0; }
    local name
    name=$(api GET "/nodes/${PVE_NODE}/qemu/${PVE_VM_ID}/config" | jq -r '.data.name')
    [[ "$name" == spinifex-ol9-* ]] || { echo "Refusing to destroy non-Spinifex VM: $name" >&2; exit 1; }
    api POST "/nodes/${PVE_NODE}/qemu/${PVE_VM_ID}/status/stop" >/dev/null || true
    sleep 2
    api DELETE "/nodes/${PVE_NODE}/qemu/${PVE_VM_ID}?purge=1&destroy-unreferenced-disks=1" >/dev/null
    # Deletion is asynchronous on some storage backends. Do not return until
    # the VM ID has disappeared, otherwise an immediate create races Proxmox.
    for _ in $(seq 1 30); do
        vm_exists || break
        sleep 2
    done
    vm_exists && { echo "Timed out waiting for VM ${PVE_VM_ID} deletion" >&2; return 1; }
    echo "Destroyed disposable VM ${PVE_VM_ID}. The uploaded seed ISO is retained for inspection."
}

case "$ACTION" in
    create) create_vm ;;
    destroy) destroy_vm ;;
    *) echo "Usage: $0 {create|destroy}" >&2; exit 2 ;;
esac
