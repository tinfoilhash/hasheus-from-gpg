#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying rclone'

package_name='rclone'
repo='rclone/rclone'
key_fingerprints=(
  'FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA' # https://rclone.org/KEYS
)
shasum_filename_pattern='SHA256SUMS'
shasum_signature_filename_pattern="$shasum_filename_pattern"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
