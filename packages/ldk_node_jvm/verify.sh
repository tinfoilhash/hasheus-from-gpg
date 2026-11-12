#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/directory.sh

check_dependencies

echo '--- verifying ldk node jvm bindings'

package_name='ldk_node_jvm'
repo='https://repo.maven.apache.org/maven2/org/lightningdevkit/ldk-node-jvm'
key_fingerprints=(
  'BD6EED4D339EDBF7E7CE7F8836153082BDF676FD' # https://github.com/tnull.gpg
)

verify_with_signed_files "$package_name" "$repo" .asc \
  "${key_fingerprints[@]}"
