#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying seedsigner'

package_name='seedsigner'
repo='SeedSigner/seedsigner'
key_fingerprints=(
  '46739B74B56AD88F14B0882EC7EF709007260119' # https://keybase.io/seedsigner/pgp_keys.asc
)
shasum_filename_pattern='seedsigner.{{NAME}}.sha256.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern.sig"

verify_from_github "$package_name" "$repo" "$shasum_filename_pattern" "$shasum_signature_filename_pattern" "${key_fingerprints[@]}"
