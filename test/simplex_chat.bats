#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup_file() {
  setup_keyring
}

teardown_file() {
  teardown_keyring
}

sign_simplex_release() {
  local tag="$1"
  local signer="${2:-signer}"
  local directory="$FAKE_GH_ROOT/$tag"
  sign_detached "$signer" "$directory/_sha256sums" \
    "$directory/_sha256sums.asc"
  local filename
  for filename in simplex-aarch64.apk simplex-armv7a.apk; do
    sign_detached "$signer" "$directory/$filename" \
      "$directory/_$filename.asc"
  done
}

setup() {
  create_repo simplex_chat
  set_key_fingerprints simplex_chat "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  export FAKE_GH_ROOT="$FAKE_CURL_ROOT/github.example"
  local tag filename
  for tag in v7.0.2 v7.0.3; do
    local directory="$FAKE_GH_ROOT/$tag"
    mkdir -p "$directory"
    for filename in simplex-chat-ubuntu-24_04-x86_64.deb \
      simplex-aarch64.apk simplex-armv7a.apk; do
      echo "$tag $filename" > "$directory/$filename"
    done
    local hash
    filename=simplex-chat-ubuntu-24_04-x86_64.deb
    hash=$(shasum -a 256 "$directory/$filename")
    echo "${hash%% *}  $tag/$filename" > "$directory/_sha256sums"
    echo license > "$directory/LICENSE"
  done
  sign_simplex_release v7.0.3
  echo '[{"tagName":"v7.0.3","publishedAt":"2026-02-01T00:00:00Z"},
    {"tagName":"v7.0.2","publishedAt":"2026-01-01T00:00:00Z"}]' \
    > "$FAKE_GH_ROOT/releases.json"
}

@test 'simplex skips old missing signatures and does not revisit the release' {
  run "$repo_dir/packages/simplex_chat/verify.sh"
  [ "$status" -eq 0 ]
  local expected='simplex-aarch64.apk simplex-armv7a.apk'
  published_is "$expected simplex-chat-ubuntu-24_04-x86_64.deb"
  [ "$(state_of simplex_chat)" = '2026-02-01T00:00:00Z' ]
  [ ! -f "$XDG_CONFIG_HOME/hasheus-from-gpg/simplex_chat.pending.json" ]
  sign_simplex_release v7.0.2
  run "$repo_dir/packages/simplex_chat/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$FAKE_HASHEUS_LOG" | tr -d ' ')" = 3 ]
  [ -z "$(leftover_files simplex_chat)" ]
}

@test 'simplex retries a recent release until its signatures arrive' {
  local recent newest
  recent=$(jaq -rn 'now - 3600 | floor | todate')
  newest=$(jaq -rn 'now | floor | todate')
  jaq --arg recent "$recent" --arg newest "$newest" '
    .[0].publishedAt = $newest | .[1].publishedAt = $recent
  ' "$FAKE_GH_ROOT/releases.json" > releases.new
  mv releases.new "$FAKE_GH_ROOT/releases.json"
  run "$repo_dir/packages/simplex_chat/verify.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'waiting for the next run'* ]]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of simplex_chat)" ]
  sign_simplex_release v7.0.2
  run "$repo_dir/packages/simplex_chat/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$FAKE_HASHEUS_LOG" | tr -d ' ')" = 6 ]
  [ "$(state_of simplex_chat)" = "$newest" ]
}

@test 'simplex also applies the upload window to partial android signatures' {
  sign_simplex_release v7.0.2
  rm "$FAKE_GH_ROOT/v7.0.2/_simplex-armv7a.apk.asc"
  local recent
  recent=$(jaq -rn 'now - 3600 | floor | todate')
  jaq -n --arg recent "$recent" \
    '[{tagName: "v7.0.2", publishedAt: $recent}]' \
    > "$FAKE_GH_ROOT/releases.json"
  run "$repo_dir/packages/simplex_chat/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$FAKE_HASHEUS_LOG" | tr -d ' ')" = 2 ]
  [ -z "$(state_of simplex_chat)" ]
  echo '[{"tagName":"v7.0.2","publishedAt":"2026-01-01T00:00:00Z"}]' \
    > "$FAKE_GH_ROOT/releases.json"
  run "$repo_dir/packages/simplex_chat/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(state_of simplex_chat)" = '2026-01-01T00:00:00Z' ]
  [ "$(wc -l < "$FAKE_HASHEUS_LOG" | tr -d ' ')" = 2 ]
}

@test 'simplex never publishes a manifest from an unlisted signer' {
  sign_simplex_release v7.0.2 stranger
  run "$repo_dir/packages/simplex_chat/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of simplex_chat)" ]
  sign_simplex_release v7.0.2
  run "$repo_dir/packages/simplex_chat/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$FAKE_HASHEUS_LOG" | tr -d ' ')" = 6 ]
}

@test 'simplex dry runs do not publish or record releases' {
  export DRY_RUN=1
  unset HASHEUS_SECRET_KEY
  run "$repo_dir/packages/simplex_chat/verify.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of simplex_chat)" ]
  [ ! -f "$XDG_CONFIG_HOME/hasheus-from-gpg/simplex_chat.pending.json" ]
}
