#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup_file() {
  setup_keyring
}

teardown_file() {
  teardown_keyring
}

prepare_forgejo_release() {
  local package_name="$1"
  local host="$2"
  local repo="$3"
  local tag="$4"
  local prefix="$5"
  local suffix="$6"
  local filename="$7"

  create_repo "$package_name"
  set_key_fingerprints "$package_name" "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  local api="$FAKE_CURL_ROOT/$host/api/v1/repos/$repo/releases"
  mkdir -p "$api/tags" "$FAKE_CURL_ROOT/${prefix#https://}"
  local payload="$FAKE_CURL_ROOT/${prefix#https://}/$filename"
  echo 'release file' > "$payload"
  sign_detached "${RELEASE_SIGNER:-signer}" "$payload" "$payload$suffix"
  jaq -n --arg tag "$tag" '[{
    tag_name: $tag, draft: false, published_at: "2026-01-01T01:00:00+01:00"
  }]' > "$api?limit=3"
  jaq -n --arg prefix "$prefix" --arg filename "$filename" \
    --arg suffix "$suffix" '{ assets: [
    {name: $filename, browser_download_url: $prefix + "/" + $filename},
    {name: ($filename + $suffix),
      browser_download_url: $prefix + "/" + $filename + $suffix},
    {name: "unsigned.txt", browser_download_url: $prefix + "/unsigned.txt"}
  ] }' > "$api/tags/$tag"
  export FAKE_ASSETS_JSON="$api/tags/$tag"
}

prepare_librewolf() {
  prepare_forgejo_release librewolf librewolf.dev librewolf/bsys6 160.0-1 \
    https://dl.librewolf.net/librewolf/160.0-1 .sig \
    librewolf-160.0-1-linux-x86_64.AppImage
}

@test 'librewolf uses the current forgejo api and external signed files' {
  prepare_librewolf
  run "$repo_dir/packages/librewolf/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(published)" = 'librewolf-160.0-1-linux-x86_64.AppImage' ]
  [ "$(state_of librewolf)" = '2026-01-01T00:00:00Z' ]
}

@test 'librewolf retries a signature from an unlisted key' {
  RELEASE_SIGNER=stranger prepare_librewolf
  run "$repo_dir/packages/librewolf/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of librewolf)" ]
}

@test 'forgejo verifies signed codeberg release files' {
  prepare_forgejo_release forgejo codeberg.org forgejo/forgejo v17.0.1 \
    https://codeberg.org/forgejo/forgejo/releases/download/v17.0.1 .asc \
    forgejo-17.0.1-linux-arm64.xz
  run "$repo_dir/packages/forgejo/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(published)" = 'forgejo-17.0.1-linux-arm64.xz' ]
  [ "$(state_of forgejo)" = '2026-01-01T00:00:00Z' ]
}

@test 'forgejo rejects unsafe asset names before downloading files' {
  prepare_librewolf
  jaq '.assets[0].name = "../outside"' "$FAKE_ASSETS_JSON" > assets.new
  mv assets.new "$FAKE_ASSETS_JSON"
  run "$repo_dir/packages/librewolf/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of librewolf)" ]
}
