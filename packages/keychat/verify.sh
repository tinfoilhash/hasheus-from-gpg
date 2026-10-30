#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying keychat'

package_name='keychat'
repo='keychat-io/keychat-app'
key_fingerprints=(
  '6148AFB29A77E655C6E22567546B80237DAF6BDA' # https://raw.githubusercontent.com/keychat-io/keychat-app/main/PGP-KEY.asc
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
