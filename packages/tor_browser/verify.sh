#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/directory.sh

check_dependencies

echo '--- verifying tor browser'

package_name='tor_browser'
repo='https://dist.torproject.org/torbrowser'
key_fingerprints=(
  'EF6E286DDA85EA2A4BA7DE684E2C6E8793298290' # https://keys.openpgp.org/vks/v1/by-fingerprint/EF6E286DDA85EA2A4BA7DE684E2C6E8793298290
)
shasum_filename_pattern='sha256sums-signed-build.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern.asc"

verify_with_manifest "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
