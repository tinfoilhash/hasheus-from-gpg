#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying kopia'

package_name='kopia'
repo='kopia/kopia'
key_fingerprints=(
  '7FB99DFD47809F0D5339D7D92273699AFD56A556' # https://kopia.io/signing-key
)
shasum_filename_pattern='checksums.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern.sig"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
