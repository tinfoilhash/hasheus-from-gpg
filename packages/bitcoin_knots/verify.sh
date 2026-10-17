#!/bin/sh

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir"

source ../../common/github.sh

check_dependencies

echo '--- verifying bitcoin knots'

package_name='bitcoin_knots'
repo='bitcoinknots/bitcoin'
key_fingerprints=(
  '1A3E761F19D2CC7785C5502EA291A2C45D0C504A' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/luke-jr.gpg
  '1D70CBE4B42239445617D33DD316C8140185B647' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/shiny.gpg
  'C1BCB7169AF1A07A0C5E471A047509FA0A6D7350' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/ataraxia.gpg
  '1D5889CB9E0564C154E18BB512EC9519DB43CC27' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/mhr6091.gpg
  'DAED928C727D3E613EC46635F5073C4F4882FFFC' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/leo-haf.gpg
  '658E64021E5793C6C4E15E45C2E581F5B998F30E' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/chrisguida.gpg
  'F68650A2E112BFAD08454264CFB2E7C306F13F5D' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/oomahq.gpg
)
shasum_filename_pattern='SHA256SUMS'
shasum_signature_filename_pattern="$shasum_filename_pattern.asc"

verify_from_github "$package_name" "$repo" "$shasum_filename_pattern" "$shasum_signature_filename_pattern" "${key_fingerprints[@]}"
