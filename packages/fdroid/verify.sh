#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/releases.sh

check_dependencies

echo '--- verifying f-droid'

package_name='fdroid'
repo='https://f-droid.org/repo'
key_fingerprints=(
  '37D2C98789D8311948394E3E41E7044E1DBA2E89' # https://keys.openpgp.org/vks/v1/by-fingerprint/37D2C98789D8311948394E3E41E7044E1DBA2E89
)

fdroid_versions() {
  local index
  index=$(curl -fsSL --compressed --max-time 60 "$repo/index-v2.json") \
    || return 1
  jaq '[.packages["org.fdroid.fdroid"].versions[] | if
    (.file.name | test("^/org[.]fdroid[.]fdroid_[0-9]+[.]apk$")) and
    (.file.sha256 | test("^[0-9a-f]{64}$")) and
    (.manifest.versionCode | type) == "number" then {
      tagName: (.manifest.versionCode | tostring),
      publishedAt: (.added / 1000 | floor | todate),
      file: .file
    } else error("invalid f-droid client entry") end
  ] | sort_by(.publishedAt) | reverse' <<< "$index"
}

list_releases() {
  jaq --argjson limit "${limit:?release limit is not set}" \
    '.[:$limit]' <<< "$fdroid_releases"
}

list_release_assets() {
  local tag="$2"
  jaq --arg tag "$tag" --arg repo "$repo" '{ assets: [
    .[] | select(.tagName == $tag) | .file as $file
    | ($file.name | ltrimstr("/")) as $name
    | {name: $name, url: $repo + $file.name,
       digest: "sha256:" + $file.sha256,
       contentType: "application/vnd.android.package-archive"},
      {name: $name + ".asc", url: $repo + $file.name + ".asc",
       contentType: "application/pgp-signature", checkAvailability: true}
  ] }' <<< "$fdroid_releases"
}

fdroid_releases=$(fdroid_versions) || exit 1
verify_with_signed_files "$package_name" "$repo" .asc \
  "${key_fingerprints[@]}"
