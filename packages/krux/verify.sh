#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying krux'

package_name='krux'
repo='selfcustody/krux'
key_fingerprints=(
  '6DC76DC81B5C35D7F432712945D7F41053AF05F3' # https://github.com/jdlcdl.gpg
)
shasum_filename_pattern='SHA256SUMS'
shasum_signature_filename_pattern='SHA256SUMS.asc'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
