#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying robosats'

package_name='robosats'
repo='RoboSats/robosats'
key_fingerprints=(
  '8FCDBF574CCFD73DB68B00CC2F7F61C6146AB157' # https://keys.openpgp.org/vks/v1/by-fingerprint/8FCDBF574CCFD73DB68B00CC2F7F61C6146AB157
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
