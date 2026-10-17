#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying zeus'

package_name='zeus'
repo='ZeusLN/zeus'
key_fingerprints=(
  '96C225207F2137E278C31CF7AAC48DE8AB8DEE84' # https://raw.githubusercontent.com/ZeusLN/zeus/master/PGP.txt
)
shasum_filename_pattern='manifest-{{NAME}}.txt'
shasum_signature_filename_pattern='manifest-{{NAME}}.txt.sig'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
