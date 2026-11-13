#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/directory.sh

check_dependencies

echo '--- verifying lightning-kmp'

package_name='lightning_kmp'
repo='https://repo.maven.apache.org/maven2/fr/acinq/lightning/lightning-kmp-core-jvm'
key_fingerprints=(
  '76C7A61D64DFAA6ADE1AD670E648F3BF0A6B99AF' # https://github.com/sstone.gpg
)

verify_with_signed_files "$package_name" "$repo" .asc \
  "${key_fingerprints[@]}"
