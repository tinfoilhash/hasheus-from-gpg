#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying qtox'

package_name='qtox'
repo='TokTok/qTox'
key_fingerprints=(
  '94CB3CD51379B7734C5617D82DEB4706E996351E' # https://github.com/Green-Sky.gpg
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
