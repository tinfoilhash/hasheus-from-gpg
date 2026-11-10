#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying hyphanet'

package_name='hyphanet'
repo='hyphanet/fred'
key_fingerprints=(
  'B30C3D91069F81ECFEFED0B1B41A6047FD6C57F9' # https://www.hyphanet.org/assets/keyring.gpg
)
signature_suffix='.sig'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
