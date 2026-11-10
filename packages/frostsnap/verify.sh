#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying frostsnap'

package_name='frostsnap'
repo='frostsnap/frostsnap'
key_fingerprints=(
  'F19CCCCD876B6E57FB712206A9D5981F42B0EA50' # https://keys.openpgp.org/vks/v1/by-fingerprint/F19CCCCD876B6E57FB712206A9D5981F42B0EA50
)
shasum_filename_pattern='CHECKSUMS'
shasum_signature_filename_pattern="$shasum_filename_pattern.asc"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
