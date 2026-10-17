#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying phoenixd'

package_name='phoenixd'
repo='ACINQ/phoenixd'
key_fingerprints=(
  '6AA45A4C209A2D3064CF66BEE434ED292E85643A' # https://acinq.co/pgp/padioupm.asc
)
shasum_filename_pattern='SHA256SUMS.asc'
shasum_signature_filename_pattern='SHA256SUMS.asc'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
