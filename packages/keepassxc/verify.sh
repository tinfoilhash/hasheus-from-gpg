#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying keepassxc'

package_name='keepassxc'
repo='keepassxreboot/keepassxc'
key_fingerprints=(
  'BF5A669F2272CF4324C1FDA8CFB4C2166397D0D2' # https://keepassxc.org/keepassxc_master_signing_key.asc
)
signature_suffix='.sig'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
