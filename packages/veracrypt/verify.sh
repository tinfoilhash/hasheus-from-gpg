#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying veracrypt'

package_name='veracrypt'
repo='veracrypt/VeraCrypt'
key_fingerprints=(
  '5069A233D55A0EEB174A5FC3821ACD02680D16DE' # https://www.idrix.fr/VeraCrypt/VeraCrypt_PGP_public_key.asc
)
signature_suffix='.sig'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
