#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/forgejo.sh

check_dependencies

echo '--- verifying forgejo'

package_name='forgejo'
repo='forgejo/forgejo'
forgejo_url='https://codeberg.org'
key_fingerprints=(
  'EB114F5E6C0DC2BCDD183550A4B61A2DC5923710' # https://keys.openpgp.org/vks/v1/by-fingerprint/EB114F5E6C0DC2BCDD183550A4B61A2DC5923710
)
signature_suffix='.asc'

verify_with_signed_files "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
