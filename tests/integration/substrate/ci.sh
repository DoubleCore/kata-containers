#!/usr/bin/env bash
# Copyright (c) 2026 NVIDIA Corporation
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

[[ $# == 2 ]] || { echo "Usage: $0 unit|root CHECKOUT" >&2; exit 1; }
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
case "$1" in
	unit) bash "${script_dir}/run.sh" "$@" ;;
	root)
		sudo env PATH="${PATH}" GOCACHE="$(go env GOCACHE)" GOMODCACHE="$(go env GOMODCACHE)" \
			bash "${script_dir}/run.sh" "$@"
		;;
	*) echo "Unknown test suite: $1" >&2; exit 1 ;;
esac
