#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying element web'

package_name='element_web'
repo='element-hq/element-web'
key_fingerprints=(
  '712BFBEE92DCA45252DB17D7C7BE97EFA179B100' # https://packages.element.io/element-release-key.asc
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
