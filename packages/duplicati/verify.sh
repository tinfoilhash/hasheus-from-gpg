#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying duplicati'

package_name='duplicati'
repo='duplicati/duplicati'
key_fingerprints=(
  'CBD0A83118CAFD23DF82F99CC20E90473DAC703D' # https://keys.openpgp.org/vks/v1/by-fingerprint/CBD0A83118CAFD23DF82F99CC20E90473DAC703D
)

# duplicati signs each file as <file>.sig, but ships the signatures in one
# <release>.signatures.zip, which itself isn't signed.
verify_duplicati_release() {
  local published_at="$2"
  local assets="$3"
  local names="$4"

  local zip_filename
  zip_filename=$(grep -m 1 '\.signatures\.zip$' <<< "$names")
  if [ -z "$zip_filename" ]; then
    skip_release_without_files "$published_at" 'signatures zip does not exist'
    return
  fi

  echo '------- downloading signatures zip'

  download_asset "$assets" "$zip_filename" || return 1

  local zip_entries
  zip_entries=$(unzip -Z1 "$zip_filename") || return 1

  # only names that are release assets are unpacked, so an entry can't write
  # outside this directory, and plain characters keep unzip from treating
  # them as wildcards.
  local filenames=''
  local filename
  while IFS= read -r filename; do
    if [ "$filename" = "$zip_filename" ] \
      || [[ ! "$filename" =~ ^[A-Za-z0-9._+-]+$ ]] \
      || ! grep -Fxq -- "$filename.sig" <<< "$zip_entries"; then
      continue
    fi
    filenames+="$filename"$'\n'
  done <<< "$names"

  if [ -z "$filenames" ]; then
    skip_release_without_files "$published_at" 'signed files do not exist'
    return
  fi

  while IFS= read -r filename <&4; do
    [ -n "$filename" ] || continue

    echo "------- processing file: $filename"

    unzip -q -o "$zip_filename" "$filename.sig" || return 1

    local details url content_type digest
    details=$(asset_details "$assets" "$filename") || return 1
    IFS=',' read -r url content_type <<< "$details"
    digest=$(jaq -r --arg filename "$filename" \
      '.assets[] | select(.name == $filename) | .digest // ""' \
      <<< "$assets") || return 1

    publish_signed_file "$filename" "$url" "$filename.sig" "$content_type" \
      "$digest" "${key_fingerprints[@]}"

    # each release is several gb, so don't keep its files until it's done.
    rm -f "$filename" || return 1
  done 4<<< "$filenames"
}

source_state "$package_name"
check_gpg_keys "${key_fingerprints[@]}"
verify_new_releases "$package_name" "$repo" verify_duplicati_release
