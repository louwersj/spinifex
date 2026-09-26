---
title: "Oracle Linux 9"
seoTitle: "Deploy Spinifex on Oracle Linux 9 — Spinifex Docs"
description: "Deploy Spinifex on x86_64 Oracle Linux 9 with Oracle-signed RPM repositories and a shell-only installer."
category: "Install"
tags:
  - install
  - oracle linux
  - rpm
  - release
---

# Oracle Linux 9 deployment

> Contribution note — Johan Louwers added the Oracle Linux 9 deployment,
> container validation, Proxmox VM utility, and the documented compatibility
> layer that keeps the existing Spinifex service contract portable.

Spinifex supports **x86_64 Oracle Linux 9** using only Oracle-signed RPM
repositories and shell scripts. The installation does not need a Spinifex RPM
repository, EPEL, Ansible, or another configuration-management product.

## Package sources and the minimal dependency set

The normal Oracle Linux 9 BaseOS and Application Stream repositories provide
the host tools: KVM, libvirt, nbdkit, firmware, networking utilities, and
system services. The installer writes a minimal DNF definition for the public,
Oracle-signed oVirt 4.5 repositories and uses Oracle's preinstalled RPM key.
It deliberately avoids Oracle's general-purpose `oracle-ovirt-release-45-el9`
configuration RPM because that RPM also pulls UEK netfilter modules intended
for Oracle VM Manager hosts. The Oracle repositories supply this networking set:

| Purpose | Oracle package |
| --- | --- |
| Open vSwitch | `openvswitch2.17` |
| OVS IPsec helper | `openvswitch2.17-ipsec` |
| OVN central services | `ovn22.09-central` |
| OVN host/controller | `ovn22.09-host` |
| IPsec implementation | `libreswan` |

The versioned names are intentional. They prevent a later, unrelated package
from silently becoming the installed network stack. The installer asks DNF to
verify Oracle's RPM signatures; it writes only the two Oracle oVirt endpoints
and does not import a custom key.

On a UEK cloud image, OVS also needs the kernel module that Oracle ships in the
matching versioned `kernel-uek-modules-extra-$(uname -r)` package. The installer
first tries `modprobe openvswitch`; only when that module is absent does it
install the precise matching Oracle package. On an RHCK image it uses the
corresponding `kernel-modules-extra-$(uname -r)` package. It never installs a
new kernel, DKMS, EPEL, or third-party module repository.

OVS IPsec remains masked on a newly installed host. A single-node cluster has
no tunnel peer to encrypt, and a multi-node cluster must first create its
certificate material. Spinifex's existing topology-aware service helper
unmasks it only after formation establishes that IPsec is required; SELinux is
never disabled for installation.

### Why EPEL StrongSwan is not installed

Oracle Linux can enable EPEL with `oracle-epel-release-el9`, and EPEL contains
StrongSwan. It is not compatible with the Oracle oVirt OVS IPsec RPM used by
Spinifex: `openvswitch2.17-ipsec` declares a dependency on LibreSwan, and both
LibreSwan and StrongSwan provide `/usr/sbin/ipsec`. Installing both is a DNF
file conflict, not a safe fallback. The supported minimal path therefore uses
the LibreSwan package required by Oracle's own OVS RPM and leaves EPEL disabled.

### Service-name compatibility

Oracle names the OVS service `openvswitch.service` and distributes OVN
components differently from Debian. `scripts/setup.sh` writes only three tiny
local systemd adapters on OL9:

| Existing Spinifex name | Oracle-backed implementation |
| --- | --- |
| `openvswitch-switch.service` | Alias of Oracle's `openvswitch.service` |
| `ovn-central.service` | Calls Oracle's `/usr/share/ovn/scripts/ovn-ctl start_northd` |
| `ovn-ovsdb-server-nb.service`, `ovn-ovsdb-server-sb.service` | Call Oracle's `ovn-ctl` NB/SB database commands |

They add no daemon and no external tool. They preserve the service names used
by `setup-ovn.sh`, including its existing single-node and RAFT lifecycle
logic, while Oracle's packaged binaries remain the only OVS/OVN binaries on
the host.

## Install

Use this single command from a version-pinned GitHub Release. It downloads the
same helper and the same `ol9-amd64` release tarball that an end user receives;
it does not require cloning the repository, Ansible, EPEL, or a private RPM
repository:

```bash
curl -fsSL https://raw.githubusercontent.com/louwersj/spinifex/vX.Y.Z/scripts/install-ol9-spinifex.sh | \
  sudo env INSTALL_SPINIFEX_GITHUB_REPOSITORY=louwersj/spinifex \
  INSTALL_SPINIFEX_VERSION=vX.Y.Z bash
```

Replace `vX.Y.Z` with a published tag. The helper verifies OL9 and x86_64,
downloads the selected `setup.sh`, installs the matching GitHub Release asset,
checks that Oracle's OVS datapath is active, and starts `spinifex.target`.
`SPINIFEX_OL9_NETWORK_SOURCE=oracle` is the
default and only accepted source. Rejecting alternate repository values is
deliberate: it makes an installation reproducible and prevents an unsupported
mix of EPEL StrongSwan, custom OVS RPMs, and Oracle oVirt RPMs.

For an upstream release, change only the repository value:

```bash
curl -fsSL https://raw.githubusercontent.com/mulgadc/spinifex/vX.Y.Z/scripts/install-ol9-spinifex.sh | \
  sudo env INSTALL_SPINIFEX_GITHUB_REPOSITORY=mulgadc/spinifex \
  INSTALL_SPINIFEX_VERSION=vX.Y.Z bash
```

No script modification is needed when a fork merges upstream; GitHub Actions
uses the repository in which the release workflow runs.

After installation, configure the networking plane:

```bash
sudo /usr/local/share/spinifex/setup-ovn.sh --management
```

## Validation gates

The repository contains two complementary checks:

1. `scripts/setup_platform_test.sh` verifies OS selection, the x86_64 Oracle
   source policy, and fork-aware release URLs without mutating the host.
2. `scripts/lint-dnf-packages.sh oraclelinux:9` runs an x86_64 OL9 container,
   configures the same public Oracle oVirt endpoints, and resolves every
   declared package.

Container tests cannot start systemd, KVM, OVS, or an OVN datapath. Before a
release is promoted, use `scripts/proxmox-ol9-test-vm.sh` to create a clean OL9
VM, run this same installer, configure `setup-ovn.sh --management`, launch a
guest, verify DHCP/Geneve/OVN connectivity and IPsec, reboot, and repeat the
checks. Repeat the same VM gate after changes to the OL9 package list or the
compatibility units.
