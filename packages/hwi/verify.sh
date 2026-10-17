#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying hwi'

package_name='hwi'
repo='bitcoin-core/HWI'
key_fingerprints=(
  '152812300785C96444D3334D17565732E08E5E41' # https://keys.openpgp.org/vks/v1/by-fingerprint/152812300785C96444D3334D17565732E08E5E41
)
shasum_filename_pattern='SHA256SUMS.txt.asc'
shasum_signature_filename_pattern='SHA256SUMS.txt.asc'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
