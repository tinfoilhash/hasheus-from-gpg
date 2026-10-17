#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying haven'

package_name='haven'
repo='barrydeen/haven'
key_fingerprints=(
  '19243581B019B2452DA2F82870FF859890221E23' # https://raw.githubusercontent.com/barrydeen/haven/master/haven.asc
)
shasum_filename_pattern='checksums.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern.sig"

verify_from_github "$package_name" "$repo" "$shasum_filename_pattern" "$shasum_signature_filename_pattern" "${key_fingerprints[@]}"
