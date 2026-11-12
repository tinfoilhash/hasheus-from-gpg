#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/directory.sh

check_dependencies

echo '--- verifying nextcloud server'

package_name='nextcloud_server'
repo='https://download.nextcloud.com/server/releases'
key_fingerprints=(
  '28806A878AE423A28372792ED75899B9A724937A' # https://nextcloud.com/nextcloud.asc
)

list_releases() {
  directory_releases "$1/" \
    '^nextcloud-(?<version>[0-9][A-Za-z0-9.+-]*)\.(tar\.bz2|zip)$'
}

list_release_assets() {
  local assets
  assets=$(directory_assets "$1/") || return 1
  jaq --arg prefix "nextcloud-$2." \
    '.assets |= map(select(.name | startswith($prefix)))' <<< "$assets"
}

verify_with_signed_files "$package_name" "$repo" .asc \
  "${key_fingerprints[@]}"
