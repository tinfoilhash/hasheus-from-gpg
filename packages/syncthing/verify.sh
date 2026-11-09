#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying syncthing'

package_name='syncthing'
repo='syncthing/syncthing'
key_fingerprints=(
  'FBA2E162F2F44657B38F0309E5665F9BD5970C47' # https://syncthing.net/release-key.gpg
)
shasum_filename_pattern='sha256sum.txt.asc'
shasum_signature_filename_pattern="$shasum_filename_pattern"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
