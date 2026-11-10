#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying lndinit'

package_name='lndinit'
repo='lightninglabs/lndinit'
key_fingerprints=(
  'B1216AF49F6F0DBA1357F8AF511B7BDA931A770F' # https://keybase.io/kevin_lightning/pgp_keys.asc
)
shasum_filename_pattern='manifest-{{NAME}}.txt'
shasum_signature_filename_pattern='manifest-{{NAME}}.sig'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
