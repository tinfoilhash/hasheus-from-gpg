#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/forgejo.sh

check_dependencies

echo '--- verifying librewolf'

package_name='librewolf'
repo='librewolf/bsys6'
forgejo_url='https://librewolf.dev'
release_download_prefix='https://dl.librewolf.net/librewolf/'
key_fingerprints=(
  '662E3CDD6FE329002D0CA5BB40339DD82B12EF16' # https://repo.librewolf.net/pubkey.gpg
)
signature_suffix='.sig'

verify_with_signed_files "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
