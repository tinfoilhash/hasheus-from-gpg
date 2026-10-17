#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying faraday'

package_name='faraday'
repo='lightninglabs/faraday'
key_fingerprints=(
  'F4FC70F07310028424EFC20A8E4256593F177720' # https://keybase.io/guggero/pgp_keys.asc
)
shasum_filename_pattern='manifest-{{NAME}}.txt'
shasum_signature_filename_pattern='manifest-{{NAME}}.sig'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
