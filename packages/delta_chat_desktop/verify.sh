#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying delta chat desktop'

package_name='delta_chat_desktop'
repo='deltachat/deltachat-desktop'
key_fingerprints=(
  '63CD1F815BA560518376999C626E26C816951308' # https://keys.openpgp.org/vks/v1/by-fingerprint/63CD1F815BA560518376999C626E26C816951308
)
shasum_filename_pattern='signed-checksums.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern"
# used by common/releases.sh through the github adapter.
# shellcheck disable=SC2034
manifest_hash_algorithm=512

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
