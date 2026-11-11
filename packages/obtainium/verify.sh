#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying obtainium'

package_name='obtainium'
repo='ImranR98/Obtainium'
key_fingerprints=(
  '8E27EC48A4FE21C71055E2E3C4EB2B69C138EBEA' # https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x8E27EC48A4FE21C71055E2E3C4EB2B69C138EBEA
)

verify_signed_checksums_from_github "$package_name" "$repo" .sha256 .sig \
  "${key_fingerprints[@]}"
