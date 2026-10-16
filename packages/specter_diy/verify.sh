#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying specter diy'

package_name='specter_diy'
repo='cryptoadvance/specter-diy'
key_fingerprints=(
  '6F16E354F83393D6E52EC25F36ED357AB24B915F' # https://stepansnigirev.com/ss-specter-release.asc
  'F2DBC4C614C113E2B15F879ADD5C1264EBD645BE' # https://github.com/miketlk.gpg
  '9DC33CA830589DE3B3225C26EEF5756B2EA42349' # http://keyserver.ubuntu.com/pks/lookup?op=get&search=0x9dc33ca830589de3b3225c26eef5756b2ea42349
)
shasum_filename_pattern='sha256.signed.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern"

verify_from_github "$package_name" "$repo" "$shasum_filename_pattern" "$shasum_signature_filename_pattern" "${key_fingerprints[@]}"
