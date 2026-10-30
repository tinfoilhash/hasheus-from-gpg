#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying nunchuk android'

package_name='nunchuk_android'
repo='nunchuk-io/nunchuk-android'
key_fingerprints=(
  '8C8ECD3F660CA53CD878792A6E38A462ED2EF525' # https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x8C8ECD3F660CA53CD878792A6E38A462ED2EF525
)
shasum_filename_pattern='SHA256SUMS.asc'
shasum_signature_filename_pattern='SHA256SUMS.asc'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
