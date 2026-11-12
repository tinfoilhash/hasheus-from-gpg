#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/directory.sh

check_dependencies

echo '--- verifying openwrt'

package_name='openwrt'
repo='https://downloads.openwrt.org/releases'
key_fingerprints=(
  '8A8BC12F46B836C0F9CDB36F1D53D1877742E911' # https://keys.openpgp.org/vks/v1/by-fingerprint/8A8BC12F46B836C0F9CDB36F1D53D1877742E911
)

list_release_assets() {
  echo '{"assets":[]}'
}

openwrt_directories() {
  local entries
  entries=$(read_directory "$1") || return 1
  jaq -er '[.[] | .name | select(endswith("/"))] | if length == 0 then
    error("openwrt target listing is empty") else .[] end' <<< "$entries"
}

verify_openwrt_release() {
  local name="$1"
  local published_at="$2"
  local working_dir="${release_dir:?release directory is not set}"
  local target_root="$repo/$name/targets"
  local targets
  targets=$(openwrt_directories "$target_root/") || return 1

  local target
  while IFS= read -r target <&4; do
    local subtargets
    subtargets=$(openwrt_directories "$target_root/$target") || return 1
    local subtarget
    while IFS= read -r subtarget <&5; do
      local url="$target_root/$target$subtarget"
      local assets names target_dir
      assets=$(directory_assets "$url") || return 1
      names=$(jaq -r '.assets[].name' <<< "$assets") || return 1
      target_dir=$(mktemp -d "$working_dir/target.XXXXXX") || return 1
      cd "$target_dir" || return 1
      echo "------- target: $target$subtarget"
      verify_manifest_release "$name" "$published_at" "$assets" "$names" \
        sha256sums sha256sums.asc "${key_fingerprints[@]}" || return 1
      cd "$working_dir" || return 1
      rm -r "$target_dir" || return 1
    done 5<<< "$subtargets"
  done 4<<< "$targets"
}

source_state "$package_name"
check_gpg_keys "${key_fingerprints[@]}"
verify_new_releases "$package_name" "$repo" verify_openwrt_release
