#!/bin/sh

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir"

source ../../common/github.sh

check_dependencies

echo '--- verifying specter diy'

package_name='specter_diy'
repo='cryptoadvance/specter-diy'
key_fingerprints=(
  '6F16E354F83393D6E52EC25F36ED357AB24B915F' # https://stepansnigirev.com/ss-specter-release.asc
)
shasum_filename_pattern='sha256.signed.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern"

verify_from_github "$package_name" "$repo" "$shasum_filename_pattern" "$shasum_signature_filename_pattern" "${key_fingerprints[@]}"
