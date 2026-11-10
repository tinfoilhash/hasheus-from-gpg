#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying keyos'

package_name='keyos'
repo='Foundation-Devices/KeyOS'
key_fingerprints=(
  '5DBE7F185293935315E56E31CFE1890AB7FC8B64' # https://foundation.xyz/security/pgp/github-signing.asc
)
signature_suffix='.sig'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
