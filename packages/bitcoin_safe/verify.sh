#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying bitcoin safe'

package_name='bitcoin_safe'
repo='andreasgriffin/bitcoin-safe'
key_fingerprints=(
  '2759AA7148568ECCB03B76301D82124B440F612D' # https://keys.openpgp.org/vks/v1/by-fingerprint/2759AA7148568ECCB03B76301D82124B440F612D
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
