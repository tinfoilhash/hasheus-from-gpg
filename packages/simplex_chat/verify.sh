#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying simplex chat'

package_name='simplex_chat'
repo='simplex-chat/simplex-chat'
key_fingerprints=(
  'BBDF7BDAD1548B16836AF5B9D53BDFD153C366BA' # https://keys.openpgp.org/vks/v1/by-fingerprint/BBDF7BDAD1548B16836AF5B9D53BDFD153C366BA
)

verify_simplex_release() {
  local name="$1"
  local published_at="$2"
  local assets="$3"
  local names="$4"
  local incomplete=false
  if grep -Fxq _sha256sums <<< "$names" \
    && grep -Fxq _sha256sums.asc <<< "$names"; then
    verify_manifest_release "$name" "$published_at" "$assets" "$names" \
      _sha256sums _sha256sums.asc "${key_fingerprints[@]}" || return 1
  else
    echo 'linux checksum manifest or signature is not uploaded yet'
    incomplete=true
  fi

  # android signatures have a leading underscore. the simplex.apk alias and
  # macos/windows builds lack this separate openpgp signing route.
  local filename
  for filename in simplex-aarch64.apk simplex-armv7a.apk; do
    grep -Fxq "$filename" <<< "$names" || continue
    local signature="_$filename.asc"
    if ! grep -Fxq "$signature" <<< "$names"; then
      echo "$filename signature is not uploaded yet"
      incomplete=true
      continue
    fi
    local details signature_details url content_type digest
    details=$(asset_details "$assets" "$filename") || return 1
    signature_details=$(asset_details "$assets" "$signature") || return 1
    IFS=',' read -r url content_type <<< "$details"
    digest=$(jaq -r --arg filename "$filename" \
      '.assets[] | select(.name == $filename) | .digest // ""' \
      <<< "$assets") || return 1
    publish_signed_file "$filename" "$url" "${signature_details%%,*}" \
      "$content_type" "$digest" "${key_fingerprints[@]}"
  done
  if [ "$incomplete" = true ]; then
    skip_release_without_files "$published_at" \
      'some release signatures are not uploaded yet'
  fi
}

source_state "$package_name"
check_gpg_keys "${key_fingerprints[@]}"
verify_new_releases "$package_name" "$repo" verify_simplex_release
