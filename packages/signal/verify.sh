#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/common.sh

check_dependencies

echo '--- verifying signal'

package_name='signal'
repo='signalapp/Signal-Desktop'
key_fingerprints=(
  '4B16B7232DFAA439AD791002EF9F501F13EED94C' # https://updates.signal.org/static/desktop/appimage.asc
)

source_state "$package_name"

check_gpg_keys "${key_fingerprints[@]}"

echo '----- getting list of releases'

# signal hosts its signed linux appimages outside github. use stable release
# tags for urls that stay tied to the verified version.
releases=$(gh release list --repo "$repo" --exclude-drafts \
  --exclude-pre-releases --limit "$limit" --json tagName,publishedAt) || exit 1

echo '----- checking for new releases'

new_releases=$(jaq -r --arg since "$last_release_published_at" '
  map(select(.tagName | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")))
  | map(select(.publishedAt > $since))
  | sort_by(.publishedAt)
  | .[]
  | "\(.tagName),\(.publishedAt)"
' <<< "$releases") || exit 1
new_releases_count=$(printf '%s' "$new_releases" | grep -c '^')

echo "new releases found: $new_releases_count"

if [ "$new_releases_count" -eq 0 ]; then
  exit
fi

while IFS=',' read -r name published_at; do
  echo "- $name ($published_at)"
done <<< "$new_releases"

while IFS=',' read -r name published_at <&3; do
  echo "----- new release: $name ($published_at)"

  start_release "$published_at"

  version="${name#v}"
  filename="signal-desktop_${version}_x86_64.AppImage"
  url="https://updates.signal.org/desktop/$filename"

  publish_signed_file "$filename" "$url" "$url.gpg" '' '' \
    "${key_fingerprints[@]}"

  complete_release "$package_name" "$published_at"
done 3<<< "$new_releases"
