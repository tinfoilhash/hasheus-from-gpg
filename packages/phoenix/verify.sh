#!/bin/sh

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir"

source ../../common/github.sh

check_dependencies

echo '--- verifying phoenix'

package_name='phoenix'
repo='ACINQ/phoenix'
key_fingerprints=(
  '55092314AD0547C59BDB7AE8E04E48E72C205463' # https://acinq.co/pgp/drouinf2.asc
)
shasum_filename_pattern='SHA256SUMS.asc'
shasum_signature_filename_pattern="$shasum_filename_pattern"

verify_from_github "$package_name" "$repo" "$shasum_filename_pattern" "$shasum_signature_filename_pattern" "${key_fingerprints[@]}"
