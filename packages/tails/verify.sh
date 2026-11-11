#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/releases.sh

check_dependencies

echo '--- verifying tails'

package_name='tails'
repo='https://tails.net/install/download/'
key_fingerprints=(
  'A490D0F4D311A4153E2BB7CADBB802B258ACD84F' # https://tails.net/tails-signing.key
)

tails_downloads() {
  local links
  links=$(
    set -o pipefail
    curl -fsSL --max-time 60 "$repo" | hq '{links: a | [@(href)]}' \
      | jaq -er '[.links[] | select(type == "string") | select(test(
        "^\\.\\./v2/Tails/[A-Za-z0-9_-]+/stable/latest\\.json$"))]
        | unique | if length == 0 then error("no tails metadata links")
          else .[] end'
  ) || return 1
  local downloads='[]'
  local link
  while IFS= read -r link <&5; do
    local url="https://tails.net/install/${link#../}"
    local modified metadata files
    modified=$(
      set -o pipefail
      curl -fsSL --max-time 60 --head "$url" \
        | awk 'tolower($1) == "last-modified:" {
            sub(/^[^:]+:[[:space:]]*/, ""); sub(/\r$/, ""); print
          }' | tail -n 1 \
        | jaq -Rer 'strptime("%a, %d %b %Y %H:%M:%S GMT")
            | strftime("%Y-%m-%dT%H:%M:%SZ")'
    ) || return 1
    is_valid_published_at "$modified" || return 1
    metadata=$(curl -fsSL --max-time 60 "$url") || return 1
    files=$(jaq --arg date "$modified" '
      [.installations[] | .version as $version
        | if ($version | test("^[0-9][A-Za-z0-9.+-]*$")) then .
          else error("invalid tails version") end
        | .["installation-paths"][] | .["target-files"][]
        | if (.url | test("^https://download\\.tails\\.net/tails/stable/"
              + "[A-Za-z0-9._+-]+/[A-Za-z0-9._+-]+$"))
            and (.sha256 | test("^[0-9a-f]{64}$")) then {
            name: (.url | split("/") | last), url: .url,
            contentType: "", digest: ("sha256:" + .sha256),
            version: $version, publishedAt: $date
          } else error("invalid tails download") end]
      | if length == 0 then error("empty tails metadata") else . end
    ' <<< "$metadata") || return 1
    downloads=$(jaq --argjson files "$files" '. + $files' \
      <<< "$downloads") || return 1
  done 5<<< "$links"
  echo "$downloads"
}

list_releases() {
  jaq --argjson limit "${limit:?release limit is not set}" '
    group_by(.version) | map({tagName: .[0].version,
      publishedAt: (map(.publishedAt) | max)})
    | sort_by(.publishedAt) | reverse | .[:$limit]
  ' <<< "$tails_assets"
}

list_release_assets() {
  jaq --arg version "$2" '{assets: [
    .[] | select(.version == $version) | ., {
      name: (.name + ".sig"),
      url: ("https://tails.net/torrents/files/" + .name + ".sig"),
      contentType: "", checkAvailability: true
    }
  ]}' <<< "$tails_assets"
}

tails_assets=$(tails_downloads) || exit 1
verify_with_signed_files "$package_name" "$repo" .sig \
  "${key_fingerprints[@]}"
