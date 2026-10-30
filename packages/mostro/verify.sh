#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying mostro'

package_name='mostro'
repo='MostroP2P/mostro'
key_fingerprints=(
  '2E986CA1C5E7EA1635CD059C4989CC7415A43AEC' # https://raw.githubusercontent.com/MostroP2P/mostro/main/keys/arkanoider.asc
  '9A718444050F091D3D24CF6CE15E232F243D73E6' # https://raw.githubusercontent.com/MostroP2P/mostro/main/keys/catrya.asc
  '1E41631D137BA2ADE55344F73852B843679AD6F0' # https://raw.githubusercontent.com/MostroP2P/mostro/main/keys/negrunch.asc
)
shasum_filename_pattern='manifest.txt'
shasum_signature_filename_pattern='manifest.txt.sig.*'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
