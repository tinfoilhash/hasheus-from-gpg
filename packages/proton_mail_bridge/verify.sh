#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying proton mail bridge'

package_name='proton_mail_bridge'
repo='ProtonMail/proton-bridge'
key_fingerprints=(
  'D51E64D3E63EDC3EEF7864CEE2C75D68E6234B07' # https://proton.me/download/bridge/bridge_pubkey.gpg
)
signature_suffix='.sig'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
