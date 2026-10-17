#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

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
  '2DEA254A2055EFD1DA82BB2315D2B66859703841' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/bigshiny90.gpg
  '314B8D611A0C0468498C35C52018C90B857A0571' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/innerhat-dev.gpg
  'A47D99B6DB0D715D40C59A2023AE8A8EA7E24E38' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/kwsantiago.gpg
  '982A193E3CE0EED535E09023188CBB2648416AD5' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/0xb10c.gpg
  '152812300785C96444D3334D17565732E08E5E41' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/achow101.gpg
  '95636F3538D9262765AB29BEE952E584CA8C0F45' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/bitcoinmechanic.gpg
  '9EDAFF80E080659604F4A76B2EBB056FD847F8A7' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/Emzy.gpg
  '714D731C6FA78DD1EB39C61667058F335E9FDCE4' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/greg-tonoski.gpg
  'F4FC70F07310028424EFC20A8E4256593F177720' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/guggero.gpg
  'D1DBF2C4B96F2DEBF4C16654410108112E7EA81F' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/hebasto.gpg
  '71A3B16735405025D447E8F274810B012346C9A6' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/laanwj.gpg
  '55058E8947E136A64F9E8AD5C4512A878E4AC2BF' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/nsvrn.gpg
  'ED9BDF7AD6A55E232E84524257FF9BDBCC301009' # https://raw.githubusercontent.com/bitcoinknots/guix.sigs/knots/builder-keys/Sjors.gpg
)
shasum_filename_pattern='SHA256SUMS'
shasum_signature_filename_pattern="$shasum_filename_pattern.asc"

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
