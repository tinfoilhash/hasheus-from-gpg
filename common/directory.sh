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
      | if ($lines | length) != ($pre.names | length) then
          error("unrecognized directory index")
        else [range(0; $lines | length) | . as $i | {
          name: $pre.names[$i],
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
  jaq --arg pattern "$pattern" --argjson limit "$limit" '
    [.[] | select(.name | test($pattern)) | {
      tagName: ((try (.name | capture($pattern).version) catch null)
        // (.name | rtrimstr("/"))), publishedAt: .publishedAt
    } | if .publishedAt == null then error("missing release date") else . end]
    | group_by(.tagName) | map(max_by(.publishedAt))
    | sort_by(.publishedAt) | reverse | .[:$limit]
  ' <<< "$entries"
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
