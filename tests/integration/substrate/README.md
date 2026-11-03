# Substrate microVM tests

The normal `ci.yaml` pipeline calls `run-substrate-tests.yaml` through the
existing PR and nightly entry points, with the same gate as other integration
tests. The workflow checks out upstream `main` once and uses that revision
for the worker, privileged and Kind microVM e2e suites. The Kind job uses
upstream's default guest assets. It verifies test execution and uploads the
results.

`run.sh` also defaults to upstream `main`; `SUBSTRATE_REF` selects another ref.
The runner reports the tested commit and leaves the upstream test source
unchanged. An existing checkout must be clean and match the selected ref.
All modes require Linux, Git and the Go toolchain required by Substrate's
`go.mod`. GitHub Actions reads the toolchain version from that checkout.

Run the microVM worker and VMM packages, plus the shared OCI specification tests:

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
