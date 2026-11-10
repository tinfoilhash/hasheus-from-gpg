#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying onionshare'

package_name='onionshare'
repo='onionshare/onionshare'
key_fingerprints=(
  '927F419D7EC82C2F149C1BD1403C2657CD994F73' # https://keys.openpgp.org/vks/v1/by-fingerprint/927F419D7EC82C2F149C1BD1403C2657CD994F73
  '2AE3D40A6905C8E4E8ED95ECE46A2B977C14666B' # https://keys.openpgp.org/vks/v1/by-fingerprint/2AE3D40A6905C8E4E8ED95ECE46A2B977C14666B
  '54A91143AE0AB4F7743B01FE888ED1B423A3BC99' # https://keys.openpgp.org/vks/v1/by-fingerprint/54A91143AE0AB4F7743B01FE888ED1B423A3BC99
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
