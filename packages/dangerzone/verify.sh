#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying dangerzone'

package_name='dangerzone'
repo='freedomofpress/dangerzone'
key_fingerprints=(
  'DE28AB241FA48260FAC9B8BAA7C9B38522604281' # https://keys.openpgp.org/vks/v1/by-fingerprint/DE28AB241FA48260FAC9B8BAA7C9B38522604281
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
