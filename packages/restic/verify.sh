#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying restic'

package_name='restic'
repo='restic/restic'
key_fingerprints=(
  'CF8F18F2844575973F79D4E191A6868BD3F7A907' # https://restic.net/gpg-key-alex.asc
)
shasum_filename_pattern='SHA256SUMS'
shasum_signature_filename_pattern="$shasum_filename_pattern.asc"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
