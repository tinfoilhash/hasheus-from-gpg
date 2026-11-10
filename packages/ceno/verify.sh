#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying ceno browser'

package_name='ceno'
repo='ceno-app/ceno-android'
key_fingerprints=(
  '51BE600C2711926C865DF93FC7DCC123F0DDB862' # https://keys.openpgp.org/vks/v1/by-fingerprint/51BE600C2711926C865DF93FC7DCC123F0DDB862
)
shasum_filename_pattern='sha256sums.txt'
shasum_signature_filename_pattern='sha256sums.txt.asc'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
