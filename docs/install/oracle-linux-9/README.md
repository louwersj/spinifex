---
title: "Oracle Linux 9"
seoTitle: "Deploy Spinifex Securely on Oracle Linux 9 — Spinifex Docs"
description: "Deploy Spinifex on Oracle Linux 9 hosts with the signed network runtime repository, repeatable release checks, and required virtual-machine validation."
category: "Install"
tags:
  - install
  - oracle linux
  - rpm
  - release
---

# Oracle Linux 9 deployment

> Contribution note — Johan Louwers added this deployment path, its fork-aware
> release guidance, and its explicit signed network-runtime safety boundary.

Spinifex supports Oracle Linux 9 hosts only when they are supplied with the
Spinifex OL9 network-runtime repository. This is deliberate: stock Oracle
Linux 9 does not publish a production-supported Open vSwitch/OVN package set
that satisfies Spinifex's service and IPsec requirements.

## Why a separate repository is required

The regular Oracle Linux 9 repositories contain the base host dependencies
used by Spinifex: KVM, libvirt, nbdkit, firmware, networking utilities, and
system services. They do not contain compatible `openvswitch`, `ovn`, and
`strongswan` packages. `nbdkit-devel` is available only from CodeReady Builder,
which Oracle marks unsupported; it is used only in the release builder to
compile the bundled nbdkit plugin and is never enabled on a deployed host.

Oracle's Developer/EPEL and oVirt repositories must not be enabled by the
installer. Oracle documents those repositories as development or unsupported,
and their OVS/OVN package names, versions, and systemd units are not a stable
match for Spinifex.

The network repository is therefore a release artifact owned by the Spinifex
release process. It keeps the deployed networking stack versioned, signed,
tested and independently updatable from the host operating system.

## Repository contract

Before declaring an OL9 release deployable, publish an HTTPS RPM repository
with signed metadata and signed RPMs for the supported OL9 architecture. It
must provide the following package names:

| Package | Required contents |
| --- | --- |
| `openvswitch` | `ovs-vsctl`, `ovs-appctl`, `ovs-vswitchd`, and the `openvswitch-switch.service` and `openvswitch-ipsec.service` units |
| `ovn` | `ovn-nbctl`, `ovn-sbctl`, `ovn-controller`, `ovn-northd`, and the `ovn-controller.service`, `ovn-central.service`, `ovn-northd.service`, `ovn-ovsdb-server-nb.service`, and `ovn-ovsdb-server-sb.service` units |
| `strongswan` | `/usr/sbin/ipsec` and the strongSwan starter components used by `openvswitch-ipsec` |

The packages must be built for OL9, pinned as a compatible OVS/OVN/strongSwan
set, and tested together. Do not mix packages from Fedora EPEL, oVirt, or a
different Enterprise Linux release. The repository must retain the RPMs for
every supported Spinifex release so existing hosts can reproduce an upgrade.

The public signing key must be served over HTTPS. Rotate the key through a new
repository release and test it before changing the installation instructions.

## Installing

Obtain the repository URL and its public-key URL from the release manifest,
then run the normal installer with both values. They are intentionally required
as a pair:

```bash
export SPINIFEX_OL9_NETWORK_REPO_URL='https://packages.example.com/spinifex/ol9/x86_64'
export SPINIFEX_OL9_NETWORK_REPO_GPGKEY_URL='https://packages.example.com/spinifex/RPM-GPG-KEY-spinifex'
curl -fsSL https://install.mulgadc.com | sudo -E bash
```

The installer writes `/etc/yum.repos.d/spinifex-network.repo` with both RPM and
repository-metadata signature checks enabled, then installs the base OL9 and
network-runtime packages. It refuses to continue if either value is absent or
does not use HTTPS. For an air-gapped deployment, mirror the signed repository
inside the environment and use that internal HTTPS endpoint.

The release tarball for OL9 contains an nbdkit plugin compiled against OL9's
glibc and nbdkit ABI. Use the `ol9-amd64` tarball, not a Debian/Ubuntu tarball.

### GitHub fork and upstream releases

The installer can download a version-pinned release directly from whichever
GitHub repository produced it. This avoids hard-coding a fork name in either
the installer or release workflow. For the current fork:

```bash
export INSTALL_SPINIFEX_GITHUB_REPOSITORY='louwersj/spinifex'
export INSTALL_SPINIFEX_VERSION='vX.Y.Z'
curl -fsSL https://raw.githubusercontent.com/louwersj/spinifex/vX.Y.Z/scripts/setup.sh | sudo -E bash
```

When the same change is released upstream, change only the environment value
to `mulgadc/spinifex`; no installer or workflow edit is required. GitHub
Actions supplies its active repository as `github.repository` when it creates
the release, so the release artifacts follow the fork automatically.

### What happens when this is merged upstream

Merging this feature from a fork into `mulgadc/spinifex` does not change or
invalidate fork installations. The release workflow always uploads artifacts
to the repository in which it runs:

| Release source | Installer value |
| --- | --- |
| Fork release | `INSTALL_SPINIFEX_GITHUB_REPOSITORY=louwersj/spinifex` |
| Official release | `INSTALL_SPINIFEX_GITHUB_REPOSITORY=mulgadc/spinifex` |

Existing installs that use `install.mulgadc.com` continue unchanged. A user
chooses a GitHub source only when they deliberately set
`INSTALL_SPINIFEX_GITHUB_REPOSITORY` and a version tag.

For Oracle Linux, the signed network-runtime bundle/repository must come from
the same release source as the Spinifex tarball. Do not combine a fork's
tarball with an upstream bundle, or the reverse, unless that exact pair was
published and VM-tested together. This prevents an unreviewed mix of OVS/OVN,
strongSwan, nbdkit plugin, and service-unit versions.

## Release and test gates

Container checks have a deliberately limited role:

1. `scripts/lint-dnf-packages.sh oraclelinux:9` resolves every base package
   against a clean stock Oracle Linux 9 image.
2. `scripts/setup_platform_test.sh` verifies OS selection and that the
   installer refuses an unsigned or unspecified network source.
3. `make distro-ol9-amd64` compiles the nbdkit plugin in an OL9 builder.

They cannot start KVM, systemd, Open vSwitch or an OVN datapath. Each release
must additionally pass a clean OL9 VM test using the exact signed repository:

1. Install via the two environment variables above.
2. Run `sudo /usr/local/share/spinifex/setup-ovn.sh --management`.
3. Create a cluster and launch a guest; verify DHCP, Geneve forwarding, OVN
   northbound/southbound connectivity, and IPsec when enabled.
4. Reboot the node and repeat the service and guest-network checks.
5. Upgrade from the prior supported OL9 release and repeat the checks.

Until that VM gate has passed for a specific repository release, it must not be
advertised as production-ready.
