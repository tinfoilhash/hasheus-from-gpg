#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying bluewallet'

package_name='bluewallet'
repo='BlueWallet/BlueWallet'
key_fingerprints=(
  'DDE50E034057F337DCFE6AD27B7D6FEF4DE5A001' # https://bluewallet.io/bluewallet-key.txt
)
signature_suffix='.sig'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
