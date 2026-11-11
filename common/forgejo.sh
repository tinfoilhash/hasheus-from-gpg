# shellcheck shell=bash
source "${BASH_SOURCE%/*}/releases.sh"

list_releases() {
  local repo="$1"
  local origin="${forgejo_url:?forgejo_url is not set}"
  local releases
  releases=$(curl -fsSL --max-time 60 \
    "$origin/api/v1/repos/$repo/releases?limit=$limit") || return 1
  jaq '[.[] | select(.draft != true) | {
    tagName: .tag_name, publishedAt: (.published_at | fromdate | todate)
  }] | sort_by(.publishedAt) | reverse' <<< "$releases"
}

list_release_assets() {
  local repo="$1"
  local origin="${forgejo_url:?forgejo_url is not set}"
  local tag="$2"
  local encoded_tag release
  encoded_tag=$(jaq -rn --arg tag "$tag" '$tag | @uri') || return 1
  release=$(curl -fsSL --max-time 60 \
    "$origin/api/v1/repos/$repo/releases/tags/$encoded_tag") || return 1

  local prefix
  prefix="${release_download_prefix:-$origin/$repo/releases/download/}"
  jaq --arg prefix "$prefix" '{ assets: [.assets[] | {
    name: .name, url: .browser_download_url, contentType: ""
  } | if (.name | test("^[A-Za-z0-9][A-Za-z0-9._+-]*$")) and
      (.url | startswith($prefix)) then .
    else error("unexpected forgejo asset name or download url") end
  ] }' <<< "$release"
}
