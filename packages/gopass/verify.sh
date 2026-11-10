#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying gopass'

package_name='gopass'
repo='gopasspw/gopass'
key_fingerprints=(
  'A1FAC0FD50ACA8DE1E8C44717EA70A3567E6E8D2' # https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xA1FAC0FD50ACA8DE1E8C44717EA70A3567E6E8D2
)

shasum_filename_pattern() {
  local name="$1"

  echo "gopass_${name#v}_SHA256SUMS"
}

shasum_signature_filename_pattern() {
  local name="$1"

  echo "$(shasum_filename_pattern "$name").sig"
}

verify_from_github "$package_name" "$repo" \
  shasum_filename_pattern shasum_signature_filename_pattern \
  "${key_fingerprints[@]}"
