#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying bitcoin keeper'

package_name='bitcoin_keeper'
repo='bithyve/bitcoin-keeper'
key_fingerprints=(
  '389F4CADA0785AC0E28A0C181BEBDE261DC3CF62' # https://keys.openpgp.org/vks/v1/by-fingerprint/389F4CADA0785AC0E28A0C181BEBDE261DC3CF62
)
shasum_filename_pattern='SHA256SUM.asc'
shasum_signature_filename_pattern='SHA256SUM.asc'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
