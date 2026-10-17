#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/common.sh

check_dependencies

echo '--- verifying bitcoin core'

package_name='bitcoin_core'

source_state "$package_name"

# keys from: https://github.com/bitcoin-core/guix.sigs/tree/main/builder-keys
key_fingerprints=(
  '982A193E3CE0EED535E09023188CBB2648416AD5' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/0xb10c.gpg
  '152812300785C96444D3334D17565732E08E5E41' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/achow101.gpg
  '0AD83877C1F0CD1EE9BD660AD7CC770B81FD22A8' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/benthecarman.gpg
  'C060A6635913D98A3587D7DB1C2491FFEB0EF770' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/cfields.gpg
  '101598DC823C1B5F9A6624ABA5E0907A0380E6C3' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/CoinForensics.gpg
  'D06C7DB566A0CA42271BB74EBB6735D6BF9E8E58' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/danielabrozzoni.gpg
  '590B7292695AFFA5B672CBB2E13FC145CD3F4304' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/darosior.gpg
  '8B612DE5D84D2683C5BF160410F2A3D26839321E' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/davidgumberg.gpg
  '948444FCE03B05BA5AB0591EC37B1C1D44C786EE' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/dunxen.gpg
  '9EDAFF80E080659604F4A76B2EBB056FD847F8A7' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/Emzy.gpg
  'E777299FC265DD04793070EB944D35F9AC3DB76A' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/fanquake.gpg
  '6B002C6EA3F91B1B0DF0C9BC8F617F1200A6D25C' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/glozow.gpg
  'F4FC70F07310028424EFC20A8E4256593F177720' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/guggero.gpg
  'D1DBF2C4B96F2DEBF4C16654410108112E7EA81F' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/hebasto.gpg
  'E9F76FD7F0B66653A7D893990E3908F364989888' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/ismaelsadeeq.gpg
  '287AE4CA1187C68C08B49CB2D11BD4F33F1DB499' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/jackielove4u.gpg
  '616516B8EB6ED02882FC4A7A8ADCB558C4F33D65' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/josibake.gpg
  'C388F6961FB972A95678E327F62711DBDCA8AE56' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/kvaciral.gpg
  '71A3B16735405025D447E8F274810B012346C9A6' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/laanwj.gpg
  '1A3E761F19D2CC7785C5502EA291A2C45D0C504A' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/luke-jr.gpg
  'E86AE73439625BBEE306AAE6B66D427F873CB1A3' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/m3dwards.gpg
  'A01783C082652969B9C492B5F9C5154E44D75DF8' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/maflcko.gpg
  '5B286407E1EA6FE01CF9AF48BF131C2D0536F8AC' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/marcofleon.gpg
  'AC5DDD2ED0068633D2223CFFD5DBABC9625AB5BE' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/nkatha23.gpg
  'E61773CD6E01040E2F1BD78CE7E2984B6289C93A' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/pinheadmz.gpg
  '2F78ACF677029767C8736F13747A7AE2FB0FD25B' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/satsie.gpg
  'A8FC55F3B04BA3146F3492E79303B33A305224CB' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/sedited.gpg
  '133EAC179436F14A5CF1B794860FEB804E669320' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/sipa.gpg
  '9D3CC86A72F8494342EA5FD10A41BDC3F4FAFF1C' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/sipsorcery.gpg
  'ED9BDF7AD6A55E232E84524257FF9BDBCC301009' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/Sjors.gpg
  '33C103B4B2794170546CCF7BCFB2C83C66CD792A' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/svanstaa.gpg
  '2197D5689DE3AF13B4FDABC47B18557E3AF1CDA5' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/tapcrafter.gpg
  '6A8F9C266528E25AEB1D7731C2371D91CB716EA7' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/theStack.gpg
  '28E72909F1717FE9607754F8A7BEB2621678D37D' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/vertiond.gpg
  '67AA5B46E7AF78053167FE343B8F814A784218F8' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/willcl-ark.gpg
  '79D00BAC68B56D422F945A8F8E3A8F3247DBCBBF' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/willyko.gpg
  'C5A8B1394FC9188223F99E089F81364FD4AF0DF6' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/xyephy.gpg
  '21B0C796F747F2C7966B7A00EB562DE99F42B3D1' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/xyzconstant.gpg
  '40D97A0E5A4F40B1CC582522CA247AC78DF0509C' # https://raw.githubusercontent.com/bitcoin-core/guix.sigs/refs/heads/main/builder-keys/yuvicc.gpg
)

check_gpg_keys "${key_fingerprints[@]}"

echo '----- getting list of releases'

releases=$(
  # fail if any command fails, not just the last, so a failed fetch isn't read as no new releases.
  set -o pipefail

  curl -fsS --max-time 60 https://bitcoincore.org/en/releasesrss.xml \
    | xmllint --xpath '//item/title/text()|//item/pubDate/text()' - \
    | paste - - \
    | jaq -Rn '[inputs | split("\t") as [$name, $published_at] | { name: $name, version: $name[13:], published_at: $published_at | strptime("%a, %d %b %Y %H:%M:%S %z") | strftime("%Y-%m-%dT%H:%M:%S%z") }]'
) || exit 1

echo '----- checking for new releases'

new_releases=$(jaq -r --arg since "$last_release_published_at" --arg limit "$limit" 'map(select(.published_at > $since)) | sort_by(.published_at) | reverse | [limit($limit | tonumber; .[])] | reverse | .[] | "\(.name),\(.version),\(.published_at)"' <<< "$releases") || exit 1
new_releases_count=$(printf '%s' "$new_releases" | grep -c '^')

echo "new releases found: $new_releases_count"

if [ "$new_releases_count" -eq 0 ]; then
  exit
fi

while IFS=',' read -r name version published_at; do
  echo "- $name ($published_at)"
done <<< "$new_releases"

# read from a separate file descriptor so the loop runs in this shell (letting `exit` stop the script) and nothing
# inside it can consume the list.
while IFS=',' read -r name version published_at <&3; do
  echo "----- new release: $name ($published_at)"

  version_bin_dir_url="https://bitcoincore.org/bin/bitcoin-core-$version"

  start_release "$published_at"

  echo '------- downloading hashes'

  shasum_filename='SHA256SUMS'

  download_file "$version_bin_dir_url/$shasum_filename" || exit 1

  shasum_manifest=$(< "$shasum_filename")

  echo '------- downloading gpg signatures'

  shasum_signature_filename="$shasum_filename.asc"

  download_file "$version_bin_dir_url/$shasum_signature_filename" || exit 1

  echo '------- verifying gpg signatures'

  if ! verify_gpg_signature "$shasum_signature_filename" "$shasum_filename" "${key_fingerprints[@]}"; then
    echo 'gpg signatures verification failed, exiting'
    exit 1
  fi

  # download each file only after the signature verifies and only if it isn't published yet, since a release is
  # several gb.
  while IFS= read -r shasum_line <&4; do
    filename=$(manifest_filename "$shasum_line")

    echo "------- processing file: $filename"

    publish_file "$shasum_line" "$version_bin_dir_url/$filename"
  done 4<<< "$shasum_manifest"

  complete_release "$package_name" "$published_at"
done 3<<< "$new_releases"
