#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying bitboxapp'

package_name='bitboxapp'
repo='BitBoxSwiss/bitbox-wallet-app'
key_fingerprints=(
  'DD09E41309750EBFAE0DEF63509249B068D215AE' # https://keys.openpgp.org/vks/v1/by-fingerprint/DD09E41309750EBFAE0DEF63509249B068D215AE
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
