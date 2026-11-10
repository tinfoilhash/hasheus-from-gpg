#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying ricochet refresh'

package_name='ricochet_refresh'
repo='blueprint-freespeech/ricochet-refresh'
key_fingerprints=(
  '07AA9DAA7088B94AF3D40084D83A26FDF5050FE0' # https://keys.openpgp.org/vks/v1/by-fingerprint/07AA9DAA7088B94AF3D40084D83A26FDF5050FE0
)
shasum_filename_pattern='sha256sums.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern.asc"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
