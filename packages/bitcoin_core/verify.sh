#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir"

source ../../common/common.sh

check_dependencies

echo '--- verifying bitcoin core'

package_name='bitcoin_core'

source_state "$package_name"

# A subset of keys from: https://github.com/bitcoin-core/guix.sigs/tree/main/builder-keys
key_fingerprints=(
  '982A193E3CE0EED535E09023188CBB2648416AD5' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/0xb10c.gpg
  '152812300785C96444D3334D17565732E08E5E41' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/achow101.gpg
  '0AD83877C1F0CD1EE9BD660AD7CC770B81FD22A8' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/benthecarman.gpg
  '9EDAFF80E080659604F4A76B2EBB056FD847F8A7' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/Emzy.gpg
  'E777299FC265DD04793070EB944D35F9AC3DB76A' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/fanquake.gpg
  'F4FC70F07310028424EFC20A8E4256593F177720' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/guggero.gpg
  'D1DBF2C4B96F2DEBF4C16654410108112E7EA81F' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/hebasto.gpg
  'E86AE73439625BBEE306AAE6B66D427F873CB1A3' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/m3dwards.gpg
  'E61773CD6E01040E2F1BD78CE7E2984B6289C93A' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/pinheadmz.gpg
  'A8FC55F3B04BA3146F3492E79303B33A305224CB' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/sedited.gpg
  '9D3CC86A72F8494342EA5FD10A41BDC3F4FAFF1C' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/sipsorcery.gpg
  'ED9BDF7AD6A55E232E84524257FF9BDBCC301009' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/Sjors.gpg
  '6A8F9C266528E25AEB1D7731C2371D91CB716EA7' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/theStack.gpg
  '67AA5B46E7AF78053167FE343B8F814A784218F8' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/willcl-ark.gpg
)

check_gpg_keys "${key_fingerprints[@]}"

echo '----- getting list of releases'

releases=$(
  curl -fsS --max-time 60 https://bitcoincore.org/en/releasesrss.xml \
  | xmllint --xpath '//item/title/text()|//item/pubDate/text()' - \
  | paste - - \
  | jaq -Rn '[inputs | split("\t") as [$name, $published_at] | { name: $name, version: $name[13:], published_at: $published_at | strptime("%a, %d %b %Y %H:%M:%S %z") | strftime("%Y-%m-%dT%H:%M:%S%z") }]'
)

echo '----- checking for new releases'

new_releases=$(echo "$releases" | jaq -r --arg since "$last_release_published_at" --argjson limit "$limit" 'map(select(.published_at > $since)) | sort_by(.published_at) | reverse | [limit($limit; .[])] | reverse | .[] | "\(.name),\(.version),\(.published_at)"')
new_releases_count=$(printf '%s' "$new_releases" | grep -c '^')

echo "new releases found: $new_releases_count"

if [ "$new_releases_count" -eq 0 ]; then
  exit
fi

echo "$new_releases" | while IFS=',' read -r name version published_at; do
  echo "- $name ($published_at)"
done

# Read from a separate file descriptor so the loop runs in this shell (letting `exit` stop the script) and nothing
# inside it can consume the list.
while IFS=',' read -r name version published_at <&3; do
  echo "----- new release: $name ($published_at)"

  version_bin_dir_url="https://bitcoincore.org/bin/bitcoin-core-$version"

  start_release

  echo '------- downloading hashes'

  shasum_filename='SHA256SUMS'

  download_file "$version_bin_dir_url/$shasum_filename" || exit 1

  shasum_manifest=$(<"$shasum_filename")

  echo '------- downloading gpg signatures'

  shasum_signature_filename="$shasum_filename.asc"

  download_file "$version_bin_dir_url/$shasum_signature_filename" || exit 1

  echo '------- verifying gpg signatures'

  if ! verify_gpg_signature "$shasum_signature_filename" "$shasum_filename" "${key_fingerprints[@]}"; then
    echo 'gpg signatures verification failed, skipping'
    complete_release "$package_name" "$published_at"
    continue
  fi

  # Download each file only after the signature verifies and only if it isn't published yet, since a release is
  # several GB.
  while IFS=' ' read -r hash filename <&4; do
    echo "------- processing file: $filename"

    if is_published_to_verify "$hash"; then
      echo 'file already verified, skipping'
      continue
    fi

    echo '------- downloading file'

    url="$version_bin_dir_url/$filename"

    download_file "$url" || exit 1

    content_type=$(file --mime-type -b "$filename")
    size=$(wc -c < "$filename" | tr -d ' ')

    echo "filename: $filename"
    echo "hash: $hash"
    echo "url: $url"
    echo "content type: $content_type"
    echo "size: $size"

    if [ "$(shasum -a 256 "$filename" | cut -d ' ' -f 1)" = "$hash" ]; then
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
