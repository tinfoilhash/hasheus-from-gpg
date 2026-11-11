#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies
command -v tar > /dev/null || exit 1

echo '--- verifying startos'

package_name='startos'
repo='Start9Labs/start-technologies'
key_fingerprints=(
  '5456DBFF1B9DF905041FA7765259ADFC2D63C217' # https://raw.githubusercontent.com/Start9Labs/start-technologies/master/shared-libs/crates/start-core/src/trusted_keys/initial/dev.asc
  'B416C0E67B9DF3F1718480AE7CFFDA41CA66056A' # https://raw.githubusercontent.com/Start9Labs/start-technologies/master/shared-libs/crates/start-core/src/trusted_keys/initial/aiden.asc
  'A969C8EBA8B13613D2568A85EE395832E45A6664' # https://raw.githubusercontent.com/Start9Labs/start-technologies/master/shared-libs/crates/start-core/src/trusted_keys/initial/matthill.asc
)

list_releases() {
  local page=1 releases='[]'
  while :; do
    local response filtered
    response=$(gh api "repos/$1/releases?per_page=100&page=$page") \
      || return 1
    filtered=$(jaq '[.[] | select(.draft == false
      and (.tag_name | test("^start-os/v[0-9][A-Za-z0-9.+-]*$")))
      | {tagName: .tag_name, publishedAt: .published_at}]' \
      <<< "$response") || return 1
    releases=$(jaq --argjson filtered "$filtered" '. + $filtered' \
      <<< "$releases") || return 1
    if [ "$(jaq length <<< "$releases")" -ge "$limit" ] \
      || [ "$(jaq length <<< "$response")" -lt 100 ]; then
      jaq --argjson limit "$limit" \
        'sort_by(.publishedAt) | reverse | .[:$limit]' <<< "$releases"
      return
    fi
    page=$((page + 1))
  done
}

startos_signature_members() {
  local archive="$1"
  local members types
  members=$(tar -tzf "$archive") || return 1
  types=$(
    set -o pipefail
    tar -tvzf "$archive" | cut -c 1
  ) || return 1
  if grep -qv '^[d-]$' <<< "$types"; then
    echo 'signature archive contains a link or special file' >&2
    return 1
  fi
  jaq -Rser '
    split("\n") | map(select(length > 0))
    | map(if . == "./" or . == "." then empty
        elif test("^(\\./)?[A-Za-z0-9][A-Za-z0-9._+-]*$") then .
        else error("unsafe signature archive member") end)
    | . as $members | map(ltrimstr("./")) as $names
    | if ($names | unique | length) != ($names | length) then
        error("duplicate signature archive member")
      else $members[] end
  ' <<< "$members"
}

verify_startos_release() {
  local name="$1"
  local published_at="$2"
  local assets="$3"
  local count
  count=$(jaq '[.assets[] | select(.name == "signatures.tar.gz")] | length' \
    <<< "$assets") || return 1
  if [ "$count" -ne 1 ]; then
    skip_release_without_files "$published_at" 'signature archive is missing'
    return
  fi
  download_asset "$assets" signatures.tar.gz || return 1
  local members filenames
  members=$(startos_signature_members signatures.tar.gz) || return 1
  filenames=$(jaq -Rsr '
    split("\n") | map(ltrimstr("./")
      | select(test("^startos-[A-Za-z0-9._+-]+\\.[A-Za-z0-9_-]+\\.asc$"))
      | sub("\\.[^.]+\\.asc$"; "")) | unique | .[]
  ' <<< "$members") || return 1
  if [ -z "$filenames" ]; then
    echo 'signature archive contains no image signatures, exiting'
    return 1
  fi
  local filename
  while IFS= read -r filename <&4; do
    local matches
    matches=$(jaq -Rsr --arg filename "$filename" '
      split("\n") | .[] | . as $member | ltrimstr("./")
      | select(startswith($filename + "."))
      | select(sub("\\.[^.]+\\.asc$"; "") == $filename) | $member
    ' <<< "$members") || return 1
    : > image-signatures.bin
    local member
    while IFS= read -r member <&5; do
      tar -xzOf signatures.tar.gz -- "$member" > image-signature.asc \
        || return 1
      gpg --batch --yes --dearmor --output image-signature.bin \
        image-signature.asc || return 1
      cat image-signature.bin >> image-signatures.bin || return 1
    done 5<<< "$matches"
    local url
    url="https://startos-images.nyc3.cdn.digitaloceanspaces.com/${name#start-os/}/$filename"
    download_file "$url" "$filename" || return 1
    publish_downloaded_signed_file "$filename" "$url" image-signatures.bin \
      '' '' "${key_fingerprints[@]}"
    rm -f "$filename" image-signature.asc image-signature.bin \
      image-signatures.bin || return 1
  done 4<<< "$filenames"
}

source_state "$package_name"
check_gpg_keys "${key_fingerprints[@]}"
verify_new_releases "$package_name" "$repo" verify_startos_release
