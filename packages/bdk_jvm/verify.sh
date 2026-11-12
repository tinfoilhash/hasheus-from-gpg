#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/directory.sh

check_dependencies

echo '--- verifying bdk jvm bindings'

package_name='bdk_jvm'
repo='https://repo.maven.apache.org/maven2/org/bitcoindevkit/bdk-jvm'
key_fingerprints=(
  '88AD93AC4589FD090FF3B8D12768C43E8803C6A3' # https://raw.githubusercontent.com/bitcoindevkit/bdk-ffi/master/PGP-BDK-BINDINGS.asc
)

verify_with_signed_files "$package_name" "$repo" .asc \
  "${key_fingerprints[@]}"
