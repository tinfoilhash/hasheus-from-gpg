#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying nix-bitcoin'

package_name='nix_bitcoin'
repo='fort-nix/nix-bitcoin'
key_fingerprints=(
  '36C71A37C9D988BDE82508D9B1A70E4F8DCD0366' # https://github.com/jonasnick.gpg
)
shasum_filename_pattern='SHA256SUMS.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern.asc"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
