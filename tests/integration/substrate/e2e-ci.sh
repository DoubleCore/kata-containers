#!/usr/bin/env bash
# Copyright (c) 2026 NVIDIA Corporation
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

[[ $# == 2 ]] || { echo "Usage: $0 run|report CHECKOUT" >&2; exit 1; }
mode=$1
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checkout=$(realpath "$2")
cd "${checkout}"
case "${mode}" in
	run)
		(cd "${SUBSTRATE_ASSET_DIR:?Candidate Substrate assets are required}"; sha256sum -c SHA256SUMS)
		git log -1 --format='Testing Substrate %H'
		[[ -c /dev/kvm ]] || { echo 'microVM e2e tests require /dev/kvm' >&2; exit 1; }
		sudo apt-get update
		sudo apt-get install -y kmod nfs-common
		sudo chmod a+rw /dev/kvm
		sudo modprobe nfs
		sudo modprobe nfsd
		bash hack/create-kind-cluster.sh
		go run ./cmd/ate-setup --kind deploy ate-system
		bash "${script_dir}/stage-artifacts.sh" "${SUBSTRATE_ASSET_DIR}"
		go run ./cmd/ate-setup --kind setup csi nfs
		go run ./cmd/ate-setup --kind deploy demo counter-microvm
		go run ./cmd/ate-setup --kind deploy demo egress-microvm
		bash hack/setup-e2e-egress-tls-kind.sh
		kubectl wait deployment --all-namespaces -l ate.dev/worker-pool --for=condition=Available --timeout=300s
		bash "${script_dir}/verify-artifacts.sh" "${SUBSTRATE_ASSET_DIR}" before
		E2E_SANDBOX_CLASS=microvm bash hack/run-e2e-kind.sh -args --no-color --preview="${ATE_PREVIEW:-}"
		bash "${script_dir}/verify-artifacts.sh" "${SUBSTRATE_ASSET_DIR}" after
		;;
	report)
		go -C tools/junittool run . verify -manifest "${ARTIFACTS:?}/expected-junit.txt"
		go -C tools/junittool run . report "${ARTIFACTS}"
		;;
	*) echo "Unknown e2e command: ${mode}" >&2; exit 1 ;;
esac
