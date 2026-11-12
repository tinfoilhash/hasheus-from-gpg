#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying ride the lightning'

package_name='ride_the_lightning'
repo='Ride-The-Lightning/RTL'
key_fingerprints=(
  '3E9BD4436C288039CA827A9200C9E2BC2E45666F' # https://keybase.io/suheb/pgp_keys.asc
)
signature_suffix='.asc'

list_release_assets() {
  local repo="$1"
  local tag="$2"

  if [[ ! "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
    echo 'unexpected ride the lightning release tag' >&2
    return 1
  fi

  local assets
  assets=$(github_release_assets "$repo" "$tag") || return 1
  jaq --arg tag "$tag" --arg repo "$repo" '
    if any(.assets[]; .name == ($tag + ".tar.gz.asc")) then
      .assets += [{
        name: $tag + ".tar.gz",
        url: "https://github.com/" + $repo +
          "/archive/refs/tags/" + $tag + ".tar.gz",
        contentType: "application/gzip"
      }]
    else . end
  ' <<< "$assets"
}

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
