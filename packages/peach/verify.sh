#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying peach'

package_name='peach'
repo='Peach2Peach/peach-app'
key_fingerprints=(
  '48339A19645E2E53488E0E5479E1B270FACD1BD2' # https://keys.openpgp.org/vks/v1/by-fingerprint/48339A19645E2E53488E0E5479E1B270FACD1BD2
)
# tags are like v0.69.0(397), and manifests like manifest-peach-0.69.0-397.txt.
shasum_filename_pattern='manifest-peach-*.txt'
shasum_signature_filename_pattern='manifest-peach-*.sig'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
