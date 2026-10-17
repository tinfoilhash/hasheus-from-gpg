#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying alby hub'

package_name='alby_hub'
repo='getAlby/hub'
key_fingerprints=(
  '44034424C3B03D81C2DC34D1A52447D15BFBF455' # https://raw.githubusercontent.com/getAlby/hub/master/scripts/keys/im-adithya.asc
  '5D92185938E6DBF893DCCC5BA5EABD8835092B08' # https://raw.githubusercontent.com/getAlby/hub/master/scripts/keys/rolznz.asc
)
shasum_filename_pattern='manifest.txt'
shasum_signature_filename_pattern='manifest*.txt.asc'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
