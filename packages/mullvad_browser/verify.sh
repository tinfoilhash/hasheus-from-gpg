#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying mullvad browser'

package_name='mullvad_browser'
repo='mullvad/mullvad-browser'
key_fingerprints=(
  'EF6E286DDA85EA2A4BA7DE684E2C6E8793298290' # https://keys.openpgp.org/vks/v1/by-fingerprint/EF6E286DDA85EA2A4BA7DE684E2C6E8793298290
)
shasum_filename_pattern='sha256sums-signed-build.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern.asc"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
