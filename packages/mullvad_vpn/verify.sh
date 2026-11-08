#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying mullvad vpn'

package_name='mullvad_vpn'
repo='mullvad/mullvadvpn-app'
key_fingerprints=(
  'A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF' # https://mullvad.net/media/mullvad-code-signing.asc
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
