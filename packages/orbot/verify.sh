#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying orbot'

package_name='orbot'
repo='guardianproject/orbot-android'
key_fingerprints=(
  'BBE20FD6DA48A3DD4CC7DF41A801183E69B37AA9' # https://keys.openpgp.org/vks/v1/by-fingerprint/BBE20FD6DA48A3DD4CC7DF41A801183E69B37AA9
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
