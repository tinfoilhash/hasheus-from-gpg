#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir"

source ../../common/common.sh

check_dependencies

echo '--- verifying coldcard'

package_name='coldcard'

source_state "$package_name"

key_fingerprints=(
  '4589779ADFC14F3327534EA8A3A31BAD5A2A5B10' # https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xA3A31BAD5A2A5B10
)

check_gpg_keys "${key_fingerprints[@]}"

echo '----- getting list of releases'

releases=$(
  curl -fsS --max-time 60 https://coldcard.com/downloads/all \
  | hq '{ releases: table > tbody > tr | [ { name: a, url: a | @(href) } ] }'
)

echo '----- checking for new releases'

new_releases=$(echo "$releases" | jaq -r --arg since "$last_release_published_at" --argjson limit "$limit" '.releases | map(select(.name | endswith(".dfu"))) | map(select(.name[0:15] > $since)) | sort_by(.name[0:15]) | reverse | [limit($limit; .[])] | reverse | .[] | "\(.name),\(.name[0:15]),\("https://coldcard.com" + .url)"')
new_releases_count=$(printf '%s' "$new_releases" | grep -c '^')

echo "new releases found: $new_releases_count"

if [ "$new_releases_count" -eq 0 ]; then
  exit
fi

echo "$new_releases" | while IFS=',' read -r name published_at url; do
  echo "- $name ($published_at)"
done

echo '----- downloading gpg signed hashes'

shasum_signed_filename='signatures.txt'

download_file "https://raw.githubusercontent.com/Coldcard/firmware/master/releases/$shasum_signed_filename" || exit 1

echo '----- verifying gpg signatures'

if ! verify_gpg_signature "$shasum_signed_filename" '' "${key_fingerprints[@]}"; then
  echo 'gpg signatures verification failed, exiting'
  exit 1
fi

shasum_manifest=$(gpg --decrypt "$shasum_signed_filename" 2>/dev/null)

# Read from a separate file descriptor so the loop runs in this shell (letting `exit` stop the script) and nothing
# inside it can consume the list.
while IFS=',' read -r name published_at url <&3; do
  echo "----- new release: $name ($published_at)"

  echo '------- downloading asset'

  start_release

  download_file "$url" || exit 1

  echo '------- verifying hash'

  shasum_check=$(echo "$shasum_manifest" | shasum --check --ignore-missing)

  while IFS=' ' read -r hash filename <&4; do
    if [ ! -f "$filename" ]; then
      continue
    fi

    echo '------- processing file'

    if is_published_to_verify "$hash"; then
      echo 'file already verified, skipping'
      continue
    fi

    content_type=$(file --mime-type -b "$filename")
    size=$(wc -c < "$filename" | tr -d ' ')

    echo "filename: $filename"
    echo "hash: $hash"
    echo "url: $url"
    echo "content type: $content_type"
    echo "size: $size"

    if echo "$shasum_check" | grep -Fxq "$filename: OK"; then
      echo 'verified: yes'
    else
      echo 'verified: no'
      echo 'file not verified, skipping'
      continue
    fi

    echo '------- publishing event'

    if ! publish_to_verify "$filename" "$hash" "$url" "$content_type" "$size"; then
      exit 1
    fi
  done 4<<< "$shasum_manifest"

  complete_release "$package_name" "$published_at"
done 3<<< "$new_releases"

rm "$shasum_signed_filename"
