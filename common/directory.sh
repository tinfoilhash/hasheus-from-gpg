# shellcheck shell=bash
source "${BASH_SOURCE%/*}/releases.sh"

read_directory() {
  local url="$1"
  local listing
  listing=$(
    set -o pipefail
    curl -fsSL --max-time 60 "$url" \
      | hq '{
        rows: tr | [ {name: a | @(href), cells: td | [ @text ]} ],
        pre: pre | [ {names: a | [ @(href) ], text: @text} ]
      }'
  ) || return 1

  jaq '
    def trim: gsub("^\\s+|\\s+$"; "");
    def date:
      trim | . as $value
      | ["%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S",
         "%a %b %d %H:%M:%S %Y", "%Y-%b-%d %H:%M", "%d-%b-%Y %H:%M"]
      | [ .[] | . as $format
          | try ($value | strptime($format)
            | strftime("%Y-%m-%dT%H:%M:%SZ")) catch empty ][0] // null;
    if (.pre | length) == 1 then
      .pre[0] as $pre
      | ($pre.text | split("\n") | map(trim | select(length > 0))) as $lines
      # apache fancy indexes put their column sort links (?C=N;O=D) on the
      # same line as the parent directory link.
      | ($pre.names | map(select(startswith("?") | not))) as $names
      | if ($lines | length) != ($names | length) then
          error("unrecognized directory index")
        else [range(0; $lines | length) | . as $i | {
          name: $names[$i],
          publishedAt: ((try ($lines[$i] | capture(
            "(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2} " +
            "[0-9]{2}:[0-9]{2}|" +
            "[0-9]{2}-[A-Za-z]{3}-[0-9]{4} [0-9]{2}:[0-9]{2})"
          ).date | date) catch null) // null)
        }] end
    elif (.rows | length) > 0 then
      [.rows[] | {name: .name,
        publishedAt: ([(.cells // [])[] | date | select(. != null)][0]
          // null)}]
    else error("response is not a directory index") end
    | map(select(.name // "" | test("^[A-Za-z0-9][A-Za-z0-9._+-]*/?$")))
  ' <<< "$listing"
}

directory_releases() {
  local url="$1"
  local pattern="$2"
  local entries
  entries=$(read_directory "$url") || return 1
  releases_from_directory_entries "$pattern" <<< "$entries"
}

releases_from_directory_entries() {
  local pattern="$1"
  jaq --arg pattern "$pattern" --argjson limit "$limit" '
    [.[] | select(.name | test($pattern)) | {
      tagName: ((try (.name | capture($pattern).version) catch null)
        // (.name | rtrimstr("/"))), publishedAt: .publishedAt
    } | if .publishedAt == null then error("missing release date") else . end]
    | group_by(.tagName) | map(max_by(.publishedAt))
    | sort_by(.publishedAt) | reverse | .[:$limit]
  '
}

directory_assets() {
  local url="${1%/}/"
  local pattern="${2:-.*}"
  local entries
  entries=$(read_directory "$url") || return 1
  jaq --arg url "$url" --arg pattern "$pattern" '{assets: [
    .[] | select((.name | endswith("/") | not) and (.name | test($pattern)))
    | {name: .name, url: ($url + .name), contentType: ""}
  ]}' <<< "$entries"
}

list_releases() {
  directory_releases "${1%/}/" '^[0-9][A-Za-z0-9._+-]*/$'
}

list_release_assets() {
  directory_assets "${1%/}/$2/"
}

# recurse only through safe relative folders from read_directory; never follow
# arbitrary URLs or silently omit files beyond the supported nesting depth.
directory_tree_assets() {
  local url="${1%/}/"
  local depth="${2:-0}"
  local entries assets folders
  entries=$(read_directory "$url") || return 1
  assets=$(jaq --arg url "$url" '[.[]
    | select(.name | endswith("/") | not)
    | . + {url: ($url + .name), contentType: ""}]' <<< "$entries") \
    || return 1
  folders=$(jaq -r '.[] | .name | select(endswith("/"))' <<< "$entries") \
    || return 1
  if [ -n "$folders" ] && [ "$depth" -ge 5 ]; then
    echo 'download directory nesting exceeds supported depth' >&2
    return 1
  fi
  local folder
  while IFS= read -r folder <&5; do
    [ -n "$folder" ] || continue
    local child
    child=$(directory_tree_assets "$url$folder" "$((depth + 1))") \
      || return 1
    assets=$(jaq --argjson child "$child" '. + $child.assets' \
      <<< "$assets") || return 1
  done 5<<< "$folders"
  jaq '{assets: .}' <<< "$assets"
}

# recursive indexes can repeat a filename in several architecture folders.
# pair each payload with its own URL's signature instead of joining by name.
verify_signed_files_release() {
  local published_at="$2"
  local release_assets="$3"
  local signature_suffix="$5"
  shift 5
  local jobs
  jobs=$(jaq -r --arg suffix "$signature_suffix" '
    .assets as $assets | $assets[] as $file
    | $assets[] | select(.url == ($file.url + $suffix))
    | "\($file.name),\($file.url),\(.url),\($file.contentType)"
  ' <<< "$release_assets") || return 1
  if [ -z "$jobs" ]; then
    skip_release_without_files "$published_at" 'signed files do not exist'
    return
  fi
  local filename url signature_url content_type
  while IFS=',' read -r filename url signature_url content_type <&4; do
    publish_signed_file "$filename" "$url" "$signature_url" "$content_type" \
      '' "$@"
    rm -f "$filename" "$filename$signature_suffix" || return 1
  done 4<<< "$jobs"
}
