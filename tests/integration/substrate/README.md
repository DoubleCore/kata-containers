# Substrate microVM tests

The normal `ci.yaml` pipeline builds the Substrate agent, rootfs and standard
Kata kernel, then calls `run-substrate-tests.yaml` with their artifact suffix.
This uses the same test gate as the other integration tests, through the
existing PR and nightly entry points.

The `substrate-microvm-e2e` job checks out upstream `main` and runs the Kind
microVM e2e suites against the candidate guest. Substrate provisions its normal
assets, including Cloud Hypervisor and virtiofsd. The Kind job uploads only the
candidate rootfs and standard Kata kernel, then clones Substrate's default
`SandboxConfig` version and replaces those two references. Other assets and
architectures retain their upstream values. The upstream source and asset
cache are unchanged. Test results include both configurations and candidate
SHA-256 hashes.

Before and after the suite, CI checks the live `SandboxConfig` against the
candidate rootfs and kernel hashes. It computes Substrate's bundle hash and
compares it with the default runtime reported by active microVM workers through
`kubectl ate get workers`. Missing workers or a mismatched configuration,
architecture or runtime hash fail the job. The log prints the artifact and
bundle hashes, and the results include the observed configuration, registered
worker runtimes and verification summary for both checks.

The existing amd64 and arm64 build workflows build `agent-substrate` and
`rootfs-image-substrate` in their normal component matrices. Their existing
archive step selects only the Substrate rootfs and standard kernel for
`kata-static-substrate.tar.zst`. Other release archive allowlists exclude
Substrate components. Substrate components use separate artifact names so
kata-deploy's artifact downloads do not collect them.

The normal release workflow publishes
`kata-static-substrate-VERSION-ARCH.tar.zst` alongside Kata's other archives.
Host binaries and other kernel variants are excluded.

`run.sh` also defaults to upstream `main`; `SUBSTRATE_REF` selects another ref.
The runner reports the tested commit and leaves the upstream test source
unchanged. An existing checkout must be clean and match the selected ref.
All modes require Linux, Git and the Go toolchain required by Substrate's
`go.mod`. GitHub Actions reads the toolchain version from that checkout.

The upstream Go worker/VMM tests are available locally; they do not boot the
candidate guest and are not run in this CI workflow. To run them, plus the
shared OCI specification tests:

```bash
bash tests/integration/substrate/run.sh unit /tmp/substrate-tests
```

These tests run with the race detector, three repetitions and shuffled order.
Tests requiring root privileges skip in this mode. Run them inside a disposable
Linux VM as root, with the same Go toolchain available in `PATH`:

```bash
sudo -E bash tests/integration/substrate/run.sh root /tmp/substrate-tests
```

The root mode uses private mount and network namespaces. It requires `unshare`,
network namespace and tap support, and the mount privileges the upstream tests
use. It runs the same packages, including their privileged tests. Neither mode
boots the guest image.

Boot-testing a candidate image also requires Docker. The boot helper currently
exists on Substrate PR #1967, not on `main`.
Until it is merged, select its commit and a separate checkout explicitly:

```bash
SUBSTRATE_REF=6f1597a87f092ba035f10a38b20665e8e1c41692 bash tests/integration/substrate/run.sh boot /tmp/substrate-boot-tests rootfs.img vmlinux
```

That upstream test checks PID 1, read-only ext4, hostname, diagnostic tools and
dpkg consistency. It requires those tools and an intact dpkg database, which
some standard Kata images omit. A successful test must report its own PASS;
a skip does not pass this mode. A revision without the helper fails explicitly.
The test selects KVM when accessible and QEMU TCG otherwise. It uses PMEM/DAX
on amd64 and virtio-blk on arm64.

Run all upstream e2e suites against an existing Substrate cluster:

```bash
bash tests/integration/substrate/run.sh e2e /tmp/substrate-tests -args --no-color
```

This selects the `microvm` sandbox class and delegates arguments to Substrate's
`hack/run-e2e.sh`. The cluster must have microVM workers, dependencies and the
candidate kernel/rootfs configured before this command runs. This runner does
not deploy or replace cluster assets. See the checkout's
`cmd/ate-setup/README.md` and `hack/run-e2e.sh --help` for setup and flags.
Cluster tests require a suitable KVM host; the standalone boot test can use TCG.
