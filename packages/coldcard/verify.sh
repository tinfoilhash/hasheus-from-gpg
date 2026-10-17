#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

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

# Rows also link to security status pages, so collect every link and keep the firmware files.
releases=$(
  # Fail if any command fails, not just the last, so a failed fetch isn't read as no new releases.
  set -o pipefail

  curl -fsS --max-time 60 https://coldcard.com/downloads/all \
    | hq '{ urls: table > tbody > tr a | [ @(href) ] }'
) || exit 1

echo '----- checking for new releases'

new_releases=$(jaq -r --arg since "$last_release_published_at" --argjson limit "$limit" '.urls | map(select(endswith(".dfu"))) | unique | map({ name: split("/") | last, url: ("https://coldcard.com" + .) }) | map(select(.name[0:15] > $since)) | sort_by(.name[0:15]) | reverse | [limit($limit; .[])] | reverse | .[] | "\(.name),\(.name[0:15]),\(.url)"' <<< "$releases") || exit 1
new_releases_count=$(printf '%s' "$new_releases" | grep -c '^')

echo "new releases found: $new_releases_count"

if [ "$new_releases_count" -eq 0 ]; then
  exit
fi

while IFS=',' read -r name published_at url; do
  echo "- $name ($published_at)"
done <<< "$new_releases"

echo '----- downloading gpg signed hashes'

shasum_signed_filename='signatures.txt'

download_file "https://raw.githubusercontent.com/Coldcard/firmware/master/releases/$shasum_signed_filename" || exit 1

echo '----- verifying gpg signatures'

if ! verify_gpg_signature "$shasum_signed_filename" '' "${key_fingerprints[@]}"; then
  rm "$shasum_signed_filename"
  echo 'gpg signatures verification failed, exiting'
  exit 1
fi

shasum_manifest=$(gpg --decrypt "$shasum_signed_filename" 2> /dev/null)
rm "$shasum_signed_filename"

# Read from a separate file descriptor so the loop runs in this shell (letting `exit` stop the script) and nothing
# inside it can consume the list.
while IFS=',' read -r name published_at url <&3; do
  echo "----- new release: $name ($published_at)"

  start_release

  echo "------- processing file: $name"

  shasum_line=$(awk -v name="$name" '$2 == name || $2 == "*" name' <<< "$shasum_manifest" | head -n 1)

  # The site can list new firmware before signatures.txt has its hash, so try again on the next run.
  if [ -z "$shasum_line" ]; then
    echo "$name isn't in $shasum_signed_filename yet, exiting"
    exit 1
  fi

  publish_file "$shasum_line" "$url"

  complete_release "$package_name" "$published_at"
done 3<<< "$new_releases"
