#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/directory.sh

check_dependencies

echo '--- verifying qubes os'

package_name='qubes_os'
repo='https://mirrors.edge.kernel.org/qubes/iso'
key_fingerprints=(
  'F3FA3F99D6281F7B3A3E5E871C3D9B627F3FADA4' # https://keys.qubes-os.org/keys/qubes-release-4.3-signing-key.asc
  '9C884DF3F81064A569A4A9FAE022E58F8E34D89F' # https://keys.qubes-os.org/keys/qubes-release-4.2-signing-key.asc
  '5817A43B283DE5A9181A522E1848792F9E2795E9' # https://keys.qubes-os.org/keys/qubes-release-4-signing-key.asc
)
version_pattern='^Qubes-R(?<version>[0-9][0-9A-Za-z.+-]*)-'
version_pattern+='[A-Za-z0-9_]+\.iso$'

list_releases() {
  directory_releases "$1/" "$version_pattern"
}

list_release_assets() {
  local assets
  assets=$(directory_assets "$1/") || return 1
  jaq --arg version "$2" \
    --arg pattern "${version_pattern%$}(\.DIGESTS)?(\.asc)?$" '
    .assets |= map(select(
      (try (.name | capture($pattern).version) catch null) == $version))
  ' <<< "$assets"
}

verify_with_signed_files "$package_name" "$repo" .asc \
  "${key_fingerprints[@]}"
