#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying elements'

package_name='elements'
repo='ElementsProject/elements'
key_fingerprints=(
  'BD0F3062F87842410B06A0432F656B0610604482' # https://raw.githubusercontent.com/ElementsProject/elements/master/contrib/release-signing/BD0F3062F87842410B06A0432F656B0610604482.pub
)
shasum_filename_pattern='SHA256SUMS.asc'
shasum_signature_filename_pattern='SHA256SUMS.asc'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
