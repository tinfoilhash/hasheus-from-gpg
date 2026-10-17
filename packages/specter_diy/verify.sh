#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir"

source ../../common/github.sh

check_dependencies

echo '--- verifying specter diy'

package_name='specter_diy'
repo='cryptoadvance/specter-diy'
key_fingerprints=(
  '6F16E354F83393D6E52EC25F36ED357AB24B915F' # https://stepansnigirev.com/ss-specter-release.asc
  'F2DBC4C614C113E2B15F879ADD5C1264EBD645BE' # https://github.com/miketlk.gpg
)
shasum_filename_pattern='sha256.signed.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern"

verify_from_github "$package_name" "$repo" "$shasum_filename_pattern" "$shasum_signature_filename_pattern" "${key_fingerprints[@]}"
