#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying bitbanana'

package_name='bitbanana'
repo='michaelWuensch/BitBanana'
key_fingerprints=(
  '9D6DC7616BC54E2724EF016350D945755565DB4B' # https://github.com/michaelWuensch.gpg
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
