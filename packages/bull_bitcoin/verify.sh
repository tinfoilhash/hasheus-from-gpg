#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying bull bitcoin'

package_name='bull_bitcoin'
repo='SatoshiPortal/bullbitcoin-mobile'
key_fingerprints=(
  'BC5AD8A26AACD383EF630D455AE8AC51D171F109' # https://github.com/i5hi.gpg
)
shasum_filename_pattern='HASHSUMS256'
shasum_signature_filename_pattern="$shasum_filename_pattern.asc"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
