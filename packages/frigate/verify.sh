#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying frigate'

package_name='frigate'
repo='sparrowwallet/frigate'
key_fingerprints=(
  'D4D0D3202FC06849A257B38DE94618334C674B40' # https://keybase.io/craigraw/pgp_keys.asc
)
shasum_filename_pattern='frigate-{{NAME}}-manifest.txt'
shasum_signature_filename_pattern='frigate-{{NAME}}-manifest.txt.asc'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
