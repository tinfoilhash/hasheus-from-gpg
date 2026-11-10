#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying yubico authenticator'

package_name='yubico_authenticator'
repo='Yubico/yubioath-flutter'
key_fingerprints=(
  '20EE325B86A81BCBD3E56798F04367096FBA95E8' # https://keys.openpgp.org/vks/v1/by-fingerprint/20EE325B86A81BCBD3E56798F04367096FBA95E8
  '9E885C0302F9BB9167529C2D5CBA11E6ADC7BCD1' # https://keys.openpgp.org/vks/v1/by-fingerprint/9E885C0302F9BB9167529C2D5CBA11E6ADC7BCD1
)
signature_suffix='.sig'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
