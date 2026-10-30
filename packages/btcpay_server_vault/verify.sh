#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying btcpay server vault'

package_name='btcpay_server_vault'
repo='btcpayserver/BTCPayServer.Vault'
key_fingerprints=(
  '7121BDE3555D9BE06BDDC68162FE85647DEDDA2E' # https://keybase.io/nicolasdorier/pgp_keys.asc
)
shasum_filename_pattern='SHA256SUMS.asc'
shasum_signature_filename_pattern='SHA256SUMS.asc'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
