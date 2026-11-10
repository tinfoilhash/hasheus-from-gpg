#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying ginger wallet'

package_name='ginger_wallet'
repo='GingerPrivacy/GingerWallet'
key_fingerprints=(
  'FA0B017A3E75CE65CBF7838FA8FF3767EDF5DCE9' # https://raw.githubusercontent.com/GingerPrivacy/GingerWallet/master/PGP.txt
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
