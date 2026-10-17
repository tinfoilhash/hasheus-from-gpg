#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying trezor suite'

package_name='trezor_suite'
repo='trezor/trezor-suite'
key_fingerprints=(
  'EB483B26B078A4AA1B6F425EE21B6950A2ECB65C' # https://trezor.io/security/satoshilabs-2021-signing-key.asc
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
