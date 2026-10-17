#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying amber'

package_name='amber'
repo='greenart7c3/Amber'
key_fingerprints=(
  '44F0AAEB77F373747E3D5444885822EED3A26A6D' # https://keys.openpgp.org/vks/v1/by-fingerprint/44F0AAEB77F373747E3D5444885822EED3A26A6D
)
shasum_filename_pattern='manifest-{{NAME}}.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern.sig"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
