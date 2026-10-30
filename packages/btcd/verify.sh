#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying btcd'

package_name='btcd'
repo='btcsuite/btcd'
key_fingerprints=(
  'C20A78516A0944900EBFCA29961CC8259AE675D4' # https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/ViktorT-11.asc
  '9FC6B0BFD597A94DBF09708280E5375C094198D8' # https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/bhandras.asc
  'BCEE34B0F9CD832214CE53005EA98470361ACB4F' # https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/boris.asc
  '1583B601BB57CC7CD2DF8A87E08DEA9B12B66AF6' # https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/georgetsagk.asc
  '7530B54D5E45A68760E68926019A44857735FD20' # https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/gijswijs.asc
  '32F7EA1E7A0339F7D37164B9F82D456EA023C9BF' # https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/hieblmi.asc
  'A5B61896952D9FDA83BC054CDC42612E89237182' # https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/roasbeef.asc
  '4DC235556B18694E08518DBB671103D881A5F0E4' # https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/sputn1ck.asc
  '3E9BD4436C288039CA827A9200C9E2BC2E45666F' # https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/suheb.asc
  'E85497D2DBA0EB9ADB0024279BCD95C4FF296868' # https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/yyforyongyu.asc
  '5F75437E11695F86D50C11BB1AFF9C4DCED6D666' # https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/ziggie1984.asc
)
shasum_filename_pattern='manifest-{{NAME}}.txt'
# the signature's name varies, like manifest-roasbeef-v0.26.2.sig and
# manifest-v0.27.0.txt.sig.
shasum_signature_filename_pattern='manifest-*{{NAME}}*.sig'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
