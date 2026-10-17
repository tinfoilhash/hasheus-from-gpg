#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/common.sh

check_dependencies

echo '--- verifying electrum'

package_name='electrum'

source_state "$package_name"

key_fingerprints=(
  '9914864DFC33499C6CA2BEEA22453004695506FD' # https://raw.githubusercontent.com/spesmilo/electrum/master/pubkeys/Animazing.asc
  '9EDAFF80E080659604F4A76B2EBB056FD847F8A7' # https://raw.githubusercontent.com/spesmilo/electrum/master/pubkeys/Emzy.asc
  '6694D8DE7BE8EE5631BED9502BD5824B7F9470E6' # https://raw.githubusercontent.com/spesmilo/electrum/master/pubkeys/ThomasV.asc
  'E546EA0987C09B6EE59A53F484F1BF925B1F484D' # https://raw.githubusercontent.com/spesmilo/electrum/master/pubkeys/bauerj.asc
  'AA0BC6824B397BBA99776E157ED8D82B37192688' # https://raw.githubusercontent.com/spesmilo/electrum/master/pubkeys/felixb_f321x.asc
  '41869671EE7506A17A0F75C7757E55F444D31227' # https://raw.githubusercontent.com/spesmilo/electrum/master/pubkeys/kyuupichan.asc
  '4AD64339DFA05E20B3F6AD51E7B748CDAF5E5ED9' # https://raw.githubusercontent.com/spesmilo/electrum/master/pubkeys/sombernight.asc
  '0EEDCFD5CAFB459067349B23CA9EEEC43DF911DC' # https://raw.githubusercontent.com/spesmilo/electrum/master/pubkeys/sombernight_releasekey.asc
  '33C103B4B2794170546CCF7BCFB2C83C66CD792A' # https://raw.githubusercontent.com/spesmilo/electrum/master/pubkeys/svanstaa.asc
  '3897E0672E32A42174B7A840038C09F462C24FC7' # https://raw.githubusercontent.com/spesmilo/electrum/master/pubkeys/wozz.asc
)

check_gpg_keys "${key_fingerprints[@]}"

download_url='https://download.electrum.org'

echo '----- getting list of releases'

releases=$(
  # fail if any command fails, not just the last, so a failed fetch isn't read
  # as no new releases.
  set -o pipefail

  curl -fsS --max-time 60 "$download_url/" \
    | hq '{ rows: tr | [ { name: a | @(href), cells: td | [ @text ] } ] }'
) || exit 1

echo '----- checking for new releases'

# releases are the index's version folders (like 4.8.2/ or 4.6.0b1/), dated by
# their modified time. it's in the server's time zone, so it's only compared
# with other times from the index.
new_releases=$(
  jaq -r --arg since "$last_release_published_at" --arg limit "$limit" '
    .rows
    | map(select(.name // "" | test("^[0-9][0-9a-z.]*/$")))
    | map({
      version: .name | rtrimstr("/"),
      published_at: .cells[2] | split(" ") | join("T")
    })
    | map(select(.published_at > $since))
    | sort_by(.published_at)
    | reverse
    | [limit($limit | tonumber; .[])]
    | reverse
    | .[]
    | "\(.version),\(.published_at)"
  ' <<< "$releases"
) || exit 1
new_releases_count=$(printf '%s' "$new_releases" | grep -c '^')

echo "new releases found: $new_releases_count"

if [ "$new_releases_count" -eq 0 ]; then
  exit
fi

while IFS=',' read -r version published_at; do
  echo "- $version ($published_at)"
done <<< "$new_releases"

# read from a separate file descriptor so the loop runs in this shell (letting
# `exit` stop the script) and nothing inside it can consume the list.
while IFS=',' read -r version published_at <&3; do
  echo "----- new release: $version ($published_at)"

  release_url="$download_url/$version"

  start_release "$published_at"

  echo '------- getting list of files'

  # file names come from the index and become local file names, so allow only
  # plain ones. this also drops the index's sorting and parent links.
  filenames=$(
    set -o pipefail

    curl -fsS --max-time 60 "$release_url/" \
      | hq '{ urls: tr a | [ @(href) ] }' \
      | jaq -r '
        .urls // []
        | .[]
        | select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))
      '
  ) || exit 1

  # every version folder lists files, so an empty list means the page wasn't
  # an index (like a challenge page). exit so the release is tried again.
  if [ -z "$filenames" ]; then
    echo 'no files in the folder listing, exiting'
    exit 1
  fi

  # each file's .asc has every signer's signature. the per-signer copies, like
  # <file>.ThomasV.asc, aren't signed themselves, so they're left out.
  signed_names=$(signed_filenames "$filenames" .asc)

  if [ -z "$signed_names" ]; then
    echo 'signed files do not exist, skipping'
    complete_release "$package_name" "$published_at"
    continue
  fi

  while IFS= read -r filename <&4; do
    echo "------- processing file: $filename"

    publish_signed_file "$filename" "$release_url/$filename" \
      "$release_url/$filename.asc" '' '' '' "${key_fingerprints[@]}"
  done 4<<< "$signed_names"

  complete_release "$package_name" "$published_at"
done 3<<< "$new_releases"
