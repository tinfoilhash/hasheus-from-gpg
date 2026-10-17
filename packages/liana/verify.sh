#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying liana'

package_name='liana'
repo='wizardsardine/liana'
key_fingerprints=(
  '5B63F3B97699C7EEF3B040B19B7F629A53E77B83' # https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x5b63f3b97699c7eef3b040b19b7f629a53e77b83
)

shasum_filename_pattern() {
  local name="$1"

  # remove "v" before version number. this needs a backreference, which parameter expansion doesn't support.
  local name_without_v
  # shellcheck disable=SC2001
  name_without_v=$(sed 's/v\([0-9]\)/\1/g' <<< "$name")

  echo "liana-$name_without_v-shasums.txt"
}

shasum_signature_filename_pattern() {
  local name="$1"

  echo "$(shasum_filename_pattern "$name").asc"
}

verify_from_github "$package_name" "$repo" shasum_filename_pattern shasum_signature_filename_pattern "${key_fingerprints[@]}"
