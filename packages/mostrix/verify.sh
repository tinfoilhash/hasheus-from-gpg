#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying mostrix'

package_name='mostrix'
repo='MostroP2P/mostrix'
key_fingerprints=(
  '2E986CA1C5E7EA1635CD059C4989CC7415A43AEC' # https://raw.githubusercontent.com/MostroP2P/mostrix/main/keys/arkanoider.asc
  '1E41631D137BA2ADE55344F73852B843679AD6F0' # https://raw.githubusercontent.com/MostroP2P/mostrix/main/keys/negrunch.asc
)
shasum_filename_pattern='manifest.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern.sig.*"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
