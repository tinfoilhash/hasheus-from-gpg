#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying loop'

package_name='loop'
repo='lightninglabs/loop'
key_fingerprints=(
  'DE23E73BFA8A0AD5587D2FCDE80D2F3F311FD87E' # https://github.com/alexbosworth.gpg
)
shasum_filename_pattern='manifest-{{NAME}}.txt'
shasum_signature_filename_pattern='manifest-{{NAME}}.txt.sig'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
