#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying gitea'

package_name='gitea'
repo='go-gitea/gitea'
key_fingerprints=(
  '7C9E68152594688862D62AF62D9AE806EC1592E2' # https://keys.openpgp.org/vks/v1/by-fingerprint/7C9E68152594688862D62AF62D9AE806EC1592E2
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
