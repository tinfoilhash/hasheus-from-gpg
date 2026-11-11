#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying bitcoin seed tool'

package_name='bitcoin_seed_tool'
repo='BitcoinQnA/seedtool'
key_fingerprints=(
  'EB3D738BEC6A873AC2745292CF4FE215EA6663AC' # https://raw.githubusercontent.com/BitcoinQnA/seedtool/main/RELEASE-SIGNING-KEY.asc
)
shasum_filename_pattern='signature.txt'
shasum_signature_filename_pattern="$shasum_filename_pattern"

parse_release_manifest() {
  awk '
    NF == 0 { next }
    $1 == "sha256sum" && $2 == "index.html" && NF == 3 &&
      length($3) == 64 && $3 !~ /[^0-9a-fA-F]/ {
      print $3 "  " $2
      count++
      next
    }
    { invalid = 1 }
    END { exit (invalid || count != 1) }
  '
}

verify_from_github "$package_name" "$repo" \
  "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
  "${key_fingerprints[@]}"
