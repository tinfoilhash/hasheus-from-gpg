#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/directory.sh

check_dependencies

echo '--- verifying nextcloud desktop'

package_name='nextcloud_desktop'
repo='https://download.nextcloud.com/desktop/releases'
key_fingerprints=(
  '28806A878AE423A28372792ED75899B9A724937A' # https://nextcloud.com/nextcloud.asc
)
version_pattern='^Nextcloud-(legacy-)?'
version_pattern+='(?<version>[0-9]+\.[0-9]+\.[0-9]+([a-z]+[0-9]+)?)(-|\.)'

list_releases() {
  local entries
  entries=$(jaq '[.assets[] | select(.name | endswith(".asc") | not)]' \
    <<< "$desktop_assets") || return 1
  releases_from_directory_entries "$version_pattern" <<< "$entries"
}

list_release_assets() {
  jaq --arg version "$2" --arg pattern "$version_pattern" '
    .assets |= map(select(
      (try (.name | capture($pattern).version) catch null) == $version))
  ' <<< "$desktop_assets"
}

desktop_assets=$(directory_tree_assets "$repo") || exit 1
verify_with_signed_files "$package_name" "$repo" .asc \
  "${key_fingerprints[@]}"
