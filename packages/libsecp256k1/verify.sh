#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying libsecp256k1'

package_name='libsecp256k1'
repo='bitcoin-core/secp256k1'
key_fingerprints=(
  '6A8F9C266528E25AEB1D7731C2371D91CB716EA7' # https://keys.openpgp.org/vks/v1/by-fingerprint/6A8F9C266528E25AEB1D7731C2371D91CB716EA7
  '09E03F871092E40E106E902B33BC86AB80FF5516' # https://keys.openpgp.org/vks/v1/by-fingerprint/09E03F871092E40E106E902B33BC86AB80FF5516
)
signature_suffix='.sig'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
