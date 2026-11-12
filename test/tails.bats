#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup_file() {
  setup_keyring
}

teardown_file() {
  teardown_keyring
}

setup() {
  create_repo tails
  set_key_fingerprints tails "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  local page="$FAKE_CURL_ROOT/tails.net/install/download"
  mkdir -p "$page" "$FAKE_CURL_ROOT/tails.net/torrents/files"
  echo '<a id="top">top</a>' > "$page/index.html"
  local arch format
  for arch in amd64 arm64; do
    echo "<a href=\"../v2/Tails/$arch/stable/latest.json\">download</a>" \
      >> "$page/index.html"
    local meta="$FAKE_CURL_ROOT/tails.net/install/v2/Tails/$arch/stable"
    mkdir -p "$meta"
    echo 'Last-Modified: Tue, 06 Oct 2026 00:16:00 GMT' \
      > "$meta/latest.json.headers"
    local files='[]'
    for format in iso img; do
      local filename="tails-$arch-7.17.$format"
      local path="download.tails.net/tails/stable/tails-$arch-7.17"
      mkdir -p "$FAKE_CURL_ROOT/$path"
      echo "$filename" > "$FAKE_CURL_ROOT/$path/$filename"
      sign_detached signer "$FAKE_CURL_ROOT/$path/$filename" \
        "$FAKE_CURL_ROOT/tails.net/torrents/files/$filename.sig"
      local hash
      hash=$(shasum -a 256 "$FAKE_CURL_ROOT/$path/$filename")
      files=$(jaq --arg url "https://$path/$filename" \
        --arg hash "${hash%% *}" '. + [{url: $url, sha256: $hash}]' \
        <<< "$files")
    done
    jaq '{installations: [{version: "7.17",
      "installation-paths": [{"target-files": .}]}]}' <<< "$files" \
      > "$meta/latest.json"
  done
}

@test 'tails checks every metadata architecture and image format' {
  run "$repo_dir/packages/tails/verify.sh"
  [ "$status" -eq 0 ]
  local expected='tails-amd64-7.17.img tails-amd64-7.17.iso'
  published_is "$expected tails-arm64-7.17.img tails-arm64-7.17.iso"
  [ "$(state_of tails)" = '2026-10-06T00:16:00Z' ]
}

@test 'tails does not record metadata without a valid modification date' {
  local path="$FAKE_CURL_ROOT/tails.net/install/v2/Tails/arm64/stable"
  echo 'Last-Modified: invalid' > "$path/latest.json.headers"
  run "$repo_dir/packages/tails/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of tails)" ]
}

@test 'tails skips an old release when any image signature is missing' {
  rm "$FAKE_CURL_ROOT/tails.net/torrents/files/tails-arm64-7.17.iso.sig"
  run "$repo_dir/packages/tails/verify.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ "$(state_of tails)" = '2026-10-06T00:16:00Z' ]
}

@test 'tails waits up to one day for missing image signatures' {
  local date arch
  date=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')
  for arch in amd64 arm64; do
    local meta="$FAKE_CURL_ROOT/tails.net/install/v2/Tails/$arch/stable"
    echo "Last-Modified: $date" > "$meta/latest.json.headers"
  done
  rm "$FAKE_CURL_ROOT/tails.net/torrents/files/tails-arm64-7.17.iso.sig"
  run "$repo_dir/packages/tails/verify.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of tails)" ]
  [[ "$output" == *'waiting for the next run'* ]]
}

@test 'tails retries signature server errors without recording the release' {
  export FAKE_CURL_STATUS_FILE='tails-arm64-7.17.iso.sig'
  export FAKE_CURL_STATUS=503
  run "$repo_dir/packages/tails/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of tails)" ]
}

@test 'tails retries signature timeouts without recording the release' {
  export FAKE_CURL_TRANSPORT_FAIL='tails-arm64-7.17.iso.sig'
  run "$repo_dir/packages/tails/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of tails)" ]
}
