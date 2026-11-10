#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying cryptomator'

package_name='cryptomator'
repo='cryptomator/cryptomator'
key_fingerprints=(
  '58117AFA1F85B3EEC154677D615D449FE6E6A235' # https://github.com/cryptobot.gpg
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
