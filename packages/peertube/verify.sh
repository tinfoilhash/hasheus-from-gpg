#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying peertube'

package_name='peertube'
repo='Chocobozzz/PeerTube'
key_fingerprints=(
  '0336DF981C56F77851CC4FB73BEF14A3B1574BA7' # https://raw.githubusercontent.com/Chocobozzz/PeerTube/develop/support/security/peertube-release-key.asc
  'C44AAD638367912CA93EDD57583A612D890159BE' # https://github.com/Chocobozzz.gpg
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
