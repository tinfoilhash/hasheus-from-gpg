#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying taproot assets'

package_name='taproot_assets'
repo='lightninglabs/taproot-assets'
key_fingerprints=(
  '9FC6B0BFD597A94DBF09708280E5375C094198D8' # https://raw.githubusercontent.com/lightninglabs/taproot-assets/main/scripts/keys/bhandras.asc
  '32953A65627C3C058A028802D6BAF4A5263245D6' # https://raw.githubusercontent.com/lightninglabs/taproot-assets/main/scripts/keys/darioanongba.asc
  '26984CB69EB8C4A26196F7A4D7D916376026F177' # https://raw.githubusercontent.com/lightninglabs/taproot-assets/main/scripts/keys/ellemouton.asc
  'C97AAA1470F979878F7A6DEDC3440ACF100A33B4' # https://raw.githubusercontent.com/lightninglabs/taproot-assets/main/scripts/keys/ffranr.asc
  '1583B601BB57CC7CD2DF8A87E08DEA9B12B66AF6' # https://raw.githubusercontent.com/lightninglabs/taproot-assets/main/scripts/keys/georgetsagk.asc
  '7530B54D5E45A68760E68926019A44857735FD20' # https://raw.githubusercontent.com/lightninglabs/taproot-assets/main/scripts/keys/gijswijs.asc
  'CA3287ADA03802AD031C8543B77DC7C964AAD99A' # https://raw.githubusercontent.com/lightninglabs/taproot-assets/main/scripts/keys/jtobin.asc
  'A5B61896952D9FDA83BC054CDC42612E89237182' # https://raw.githubusercontent.com/lightninglabs/taproot-assets/main/scripts/keys/roasbeef.asc
  'E85497D2DBA0EB9ADB0024279BCD95C4FF296868' # https://raw.githubusercontent.com/lightninglabs/taproot-assets/main/scripts/keys/yyforyongyu.asc
)
shasum_filename_pattern='manifest-{{NAME}}.txt'
shasum_signature_filename_pattern='manifest-*-{{NAME}}.sig'

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
