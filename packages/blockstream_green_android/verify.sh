#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying blockstream green android'

package_name='blockstream_green_android'
repo='Blockstream/green_android'
key_fingerprints=(
  '04BEBF2E35A2AF2FFDF1FA5DE7F054AA2E76E792' # https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x04BEBF2E35A2AF2FFDF1FA5DE7F054AA2E76E792
)
shasum_filename_pattern='SHA256SUMS.asc'
shasum_signature_filename_pattern='SHA256SUMS.asc'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
