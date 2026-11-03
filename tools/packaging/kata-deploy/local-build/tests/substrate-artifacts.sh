#!/usr/bin/env bash
# Copyright (c) 2026 NVIDIA Corporation
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

builder=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo=$(cd "${builder}/../../../.." && pwd)
# shellcheck source=/dev/null
source "${builder}/kata-release-tarball-inputs.sh"
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/components"
fixture() {
	local component=$1 path=$2
	mkdir -p "${work}/${component}/$(dirname "${path}")"
	printf '%s\n' "${component}" > "${work}/${component}/${path}"
	tar --zstd -cf "${work}/components/kata-static-${component}.tar.zst" -C "${work}/${component}" .
}
fixture agent-substrate usr/bin/kata-agent
fixture rootfs-image-substrate opt/kata/share/kata-containers/kata-containers-substrate.img
fixture kernel opt/kata/share/kata-containers/vmlinux-test
ln -s vmlinux-test "${work}/kernel/opt/kata/share/kata-containers/vmlinux.container"
tar --zstd -cf "${work}/components/kata-static-kernel.tar.zst" -C "${work}/kernel" .
for arch in amd64 arm64; do
	# Build every normal component as a tiny fixture so all three archives share inputs.
	while read -r name; do
		[[ -f "${work}/components/${name}" ]] && continue
		component=${name#kata-static-}
		component=${component%.tar.zst}
		fixture "${component}" "opt/kata/share/fixtures/${component}"
	done < <({ kata_static_tarball_inputs "${arch}"; kata_go_tarball_inputs "${arch}"; } | sort -u)
	(
		cd "${work}"
		RELEASE=yes bash "${builder}/kata-deploy-merge-release-tarballs.sh" components "${repo}/versions.yaml" "${arch}" > merge.log
	)
	for archive in kata-static kata-go-static; do
		tar --zstd -tf "${work}/${archive}.tar.zst" > "${work}/${archive}.contents"
		if grep -E 'substrate|usr/bin/kata-agent' "${work}/${archive}.contents"; then
			echo "Substrate leaked into ${archive} for ${arch}" >&2
			exit 1
		fi
	done
	mkdir "${work}/guest-${arch}"
	tar --zstd -xf "${work}/kata-static-substrate.tar.zst" -C "${work}/guest-${arch}"
	[[ $(find "${work}/guest-${arch}" -type f | wc -l) == 4 ]]
	[[ -f "${work}/guest-${arch}/opt/kata/versions.yaml" ]]
	[[ ! -d "${work}/guest-${arch}/opt/kata/bin" && ! -d "${work}/guest-${arch}/usr" ]]
	bash "${repo}/tests/integration/substrate/extract-artifacts.sh" \
		"${work}/kata-static-substrate.tar.zst" "${work}/assets-${arch}"
	[[ $(cat "${work}/assets-${arch}/vmlinux") == kernel ]]
	[[ $(cat "${work}/assets-${arch}/rootfs.img") == rootfs-image-substrate ]]
	(cd "${work}/assets-${arch}"; sha256sum -c SHA256SUMS)
done

# Validate the normal release command without contacting GitHub.
mkdir "${work}/bin"
cat > "${work}/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == release && $2 == upload && $# == 4 ]]
[[ $4 == "kata-static-substrate-${3}-arm64.tar.zst" && -f $4 ]]
printf '%s\n' "$3" > "${TEST_GH_CALL}"
MOCK
chmod +x "${work}/bin/gh"
export TEST_GH_CALL="${work}/uploaded"
(
	cd "${work}"
	PATH="${work}/bin:${PATH}" GH_TOKEN=test ARCHITECTURE=arm64 \
		KATA_SUBSTRATE_STATIC_TARBALL=kata-static-substrate.tar.zst \
		bash "${repo}/tools/packaging/release/release.sh" upload-kata-substrate-static-tarball
)
[[ $(cat "${work}/uploaded") == "$(cat "${repo}/VERSION")" ]]
rm "${work}/components/kata-static-kernel.tar.zst"
if RELEASE=yes bash "${builder}/kata-deploy-merge-builds.sh" "${work}/components" "" \
	"${work}/incomplete.tar.zst" "$(kata_substrate_tarball_inputs arm64)" > "${work}/missing-kernel.log" 2>&1; then
	echo 'Missing kernel must fail the guest archive build' >&2
	exit 1
fi
if kata_substrate_tarball_inputs s390x > "${work}/unsupported.log" 2>&1; then
	echo 'Unsupported Substrate architecture must fail' >&2
	exit 1
fi
echo 'Substrate guest archive, normal archive isolation and release checks passed'
