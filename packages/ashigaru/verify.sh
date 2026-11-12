#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/releases.sh

check_dependencies

echo '--- verifying ashigaru'

package_name='ashigaru'
repo='https://ashigaru.rs/download/'
key_fingerprints=(
  '445F807996F70586B715C7B8A13806B1FA2A676B' # https://keybase.io/ashigarudev/pgp_keys.asc
)
tor_proxy="${ASHIGARU_TOR_PROXY:-socks5h://127.0.0.1:9050}"
if [[ ! "$tor_proxy" =~ ^socks5h://[^[:space:]]+$ ]]; then
  echo 'ashigaru tor proxy must use socks5h://, exiting'
  exit 1
fi

download_file() {
  local url="$1"
  local filename="$2"
  curl -fL --connect-timeout 30 --speed-limit 1024 --speed-time 60 \
    --proxy "$tor_proxy" --noproxy '' -o "$filename" "$url"
}

parse_release_manifest() {
  jaq -Rser '
    def filename:
      if test("^ashigaru_[A-Za-z0-9._+-]+$") then .
      else error("invalid signed ashigaru filename") end;
    def hash:
      if test("^[0-9a-fA-F]{64}$") then ascii_downcase
      else error("invalid signed ashigaru hash") end;
    split("\n") | map(gsub("^\\s+|\\s+$"; "")) as $lines
    | if any($lines[]; startswith("File name:")) then
        reduce $lines[] as $line ({name: null, files: []};
          if ($line | startswith("File name:")) then
            if .name != null then error("unpaired signed filename")
            else .name = ($line | ltrimstr("File name: ") | filename) end
          elif ($line | startswith("SHA-256 Hash of file:")) then
            if .name == null then error("hash has no signed filename")
            else .files += [{name: .name,
              hash: ($line | ltrimstr("SHA-256 Hash of file: ") | hash)}]
              | .name = null end
          else . end)
        | if .name != null then error("signed filename has no hash")
          else .files end
      else
        [$lines[] | select(test("^ashigaru_mobile_.*\\.apk$"))] as $names
        | [range(0; $lines | length) | select(
            $lines[.] == "SHA-256 Hash of the APK file:")] as $labels
        | if ($names | length) != 1 or ($labels | length) != 1 then
            error("unrecognized signed ashigaru manifest")
          else [{name: ($names[0] | filename),
            hash: ($lines[$labels[0] + 1] | hash)}] end
      end
    | if length == 0 or (map(.name) | unique | length) != length then
        error("empty or duplicate signed ashigaru filenames")
      else .[] | "\(.hash)  \(.name)" end
  '
}

load_ashigaru_releases() {
  local messages releases='[]'
  messages=$(jaq -c '.messages[] | select(
    startswith("-----BEGIN PGP SIGNED MESSAGE-----"))' \
    <<< "$ashigaru_page") || return 1
  if [ -z "$messages" ]; then
    echo 'ashigaru signed messages are missing' >&2
    return 1
  fi
  local encoded
  while IFS= read -r encoded <&5; do
    local message timestamp date tag
    message=$(jaq -r . <<< "$encoded") || return 1
    # this date only orders attempts; the original signed message must verify
    # before any files are published or this date is recorded.
    timestamp=$(
      set -o pipefail
      awk '/^-----BEGIN PGP SIGNATURE-----$/ { printing = 1 }
        printing { print }
        /^-----END PGP SIGNATURE-----$/ { printing = 0 }' \
        <<< "$message" \
        | gpg --list-packets \
        | awk '$1 == "version" && $3 == "created" {
            gsub(/,/, "", $4); print $4
          }'
    ) || return 1
    date=$(jaq -ner --argjson timestamp "$timestamp" '$timestamp | todate') \
      || return 1
    tag=$(printf '%s' "$message" | shasum -a 256) || return 1
    releases=$(jaq --arg tag "${tag%% *}" --arg date "$date" \
      --arg message "$message" '. + [{tagName: $tag, publishedAt: $date,
        message: $message}]' <<< "$releases") || return 1
  done 5<<< "$messages"
  echo "$releases"
}

list_releases() {
  jaq --argjson limit "${limit:?release limit is not set}" \
    'unique_by(.tagName) | sort_by(.publishedAt) | reverse | .[:$limit]' \
    <<< "$ashigaru_releases"
}

list_release_assets() {
  jaq '{assets: [.links[] | select(type == "string")
    | select(test("^https?://[a-z2-7]{56}\\.onion/"
        + "[A-Za-z0-9._+/-]+$"))
    | {name: (split("/") | last), url: ., contentType: ""}
  ] | unique_by(.url)}' <<< "$ashigaru_page"
}

verify_ashigaru_release() {
  local name="$1"
  local assets="$3"
  jaq -er --arg name "$name" \
    '.[] | select(.tagName == $name) | .message' \
    <<< "$ashigaru_releases" > manifest.asc || return 1
  verify_gpg_signature manifest.asc '' "${key_fingerprints[@]}" \
    || return 1
  local manifest
  manifest=$(
    set -o pipefail
    gpg --decrypt manifest.asc | parse_release_manifest
  ) || return 1
  local line
  while IFS= read -r line <&4; do
    local filename url
    filename=$(manifest_filename "$line")
    url=$(jaq -er --arg filename "$filename" '
      [.assets[] | select(.name == $filename)]
      | if length == 1 then .[0].url
        else error("signed ashigaru file needs one onion download url") end
    ' <<< "$assets") || return 1
    publish_file "$line" "$url" ''
    rm -f "$filename" || return 1
  done 4<<< "$manifest"
}

ashigaru_page=$(
  set -o pipefail
  curl -fsSL --max-time 60 "$repo" \
    | hq '{messages: pre code | [@text], links: a | [@(href)]}'
) || exit 1
ashigaru_releases=$(load_ashigaru_releases) || exit 1
source_state "$package_name"
check_gpg_keys "${key_fingerprints[@]}"
verify_new_releases "$package_name" "$repo" verify_ashigaru_release
