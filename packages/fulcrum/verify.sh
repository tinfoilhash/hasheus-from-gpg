#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying fulcrum'

package_name='fulcrum'
repo='cculianu/Fulcrum'
key_fingerprints=(
  'D465135F97D0047E18E99DC321810A542031C02C' # https://keys.openpgp.org/vks/v1/by-fingerprint/D465135F97D0047E18E99DC321810A542031C02C
)

# file names drop the tag's "v", like Fulcrum-2.1.3-shasums.txt for v2.1.3.
shasum_filename_pattern() {
  local name="$1"

  echo "Fulcrum-${name#v}-shasums.txt"
}

shasum_signature_filename_pattern() {
  local name="$1"

  echo "$(shasum_filename_pattern "$name").asc"
}

verify_from_github "$package_name" "$repo" \
  shasum_filename_pattern shasum_signature_filename_pattern \
  "${key_fingerprints[@]}"
