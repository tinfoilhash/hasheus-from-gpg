#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying liquid gdk'

package_name='liquid_gdk'
repo='Blockstream/gdk'
key_fingerprints=(
  '129EE55E90E6E7BB5ED3530DFD9FCBA3C53CED20' # https://github.com/jgriffiths.gpg
  '569C506861E0F3D2FBC5125E24C3A2E125C994A6' # https://github.com/Mixa84.gpg
)
shasum_filename_pattern='SHA256SUMS.asc'
shasum_signature_filename_pattern="$shasum_filename_pattern"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
