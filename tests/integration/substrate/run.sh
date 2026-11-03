#!/usr/bin/env bash
# Copyright (c) 2026 NVIDIA Corporation
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

usage() {
	cat <<EOF
Usage: $0 unit CHECKOUT [go-test-flags]
       $0 root CHECKOUT [go-test-flags]
       $0 boot CHECKOUT ROOTFS KERNEL
       $0 e2e CHECKOUT [upstream-e2e-flags]

Fetches Substrate main if CHECKOUT does not exist; SUBSTRATE_REF overrides the ref.
root requires root privileges. e2e requires a deployed Substrate cluster.
EOF
}
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
	usage
	exit 0
fi
[[ $# -ge 2 ]] || { usage >&2; exit 1; }
suite=$1
checkout=$2
shift 2
[[ $(uname -s) == Linux ]] || { echo 'Substrate microVM tests require Linux' >&2; exit 1; }
case "${suite}" in
	unit|root|e2e) ;;
	boot) [[ $# == 2 ]] || { usage >&2; exit 1; } ;;
	*) usage >&2; exit 1 ;;
esac
if [[ "${suite}" == unit && ${EUID} == 0 ]]; then
	echo 'Use root mode to run privileged tests in private namespaces' >&2
	exit 1
fi
if [[ "${suite}" == root && ${EUID} != 0 ]]; then
	echo 'Run root tests as root inside a disposable Linux VM' >&2
	exit 1
fi
if [[ "${suite}" == boot ]]; then
	rootfs=$(realpath "$1")
	kernel=$(realpath "$2")
	[[ -f "${rootfs}" && -f "${kernel}" ]] || { echo 'Rootfs and kernel must exist' >&2; exit 1; }
fi
ref=${SUBSTRATE_REF:-main}
url=https://github.com/agent-substrate/substrate

if [[ ! -e "${checkout}" ]]; then
	git init "${checkout}"
	git -C "${checkout}" fetch --depth=3 "${url}" "${ref}"
	git -C "${checkout}" checkout --detach FETCH_HEAD
	if [[ "${ref}" == main ]]; then
		git -C "${checkout}" branch main FETCH_HEAD
	fi
fi
[[ $(git -C "${checkout}" rev-parse HEAD) == "$(git -C "${checkout}" rev-parse "${ref}^{commit}")" ]] || {
	echo "Substrate checkout must be at ${ref}" >&2
	exit 1
}
[[ -z $(git -C "${checkout}" status --porcelain) ]] || {
	echo 'Substrate checkout must be clean' >&2
	exit 1
}
cd "${checkout}"
git log -1 --format='Testing Substrate %H'
case "${suite}" in
	unit|root)
		# The boot test runs separately and must receive both artifacts.
		unset ATEWORKER_TEST_ROOTFS_IMG ATEWORKER_TEST_KERNEL
		command=(go test -race -count=3 -shuffle=on "$@" ./cmd/ateworker-microvm/... ./internal/ocispec)
		if [[ "${suite}" == root ]]; then
			# Keep privileged tests' mounts and network interfaces in private namespaces.
			unshare --mount --net --fork --propagation private -- "${command[@]}"
		else
			"${command[@]}"
		fi
		;;
	boot)
		[[ -f hack/microvm-assets/test-rootfs.sh ]] || {
			echo 'This Substrate revision does not provide the guest boot test' >&2
			exit 1
		}
		bash hack/microvm-assets/test-rootfs.sh "${rootfs}" "${kernel}"
		;;
	e2e) E2E_SANDBOX_CLASS=microvm bash hack/run-e2e.sh "$@" ;;
esac
