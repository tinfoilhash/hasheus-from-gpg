#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup_file() {
  setup_keyring
}

teardown_file() {
  teardown_keyring
}

tag='v2.4.1.0_stable_2026-10-29'
prefix='duplicati-2.4.1.0_stable_2026-10-29'

setup() {
  create_repo duplicati
  set_key_fingerprints duplicati "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  export FAKE_GH_ROOT="$FAKE_CURL_ROOT/github.example"
  release_dir="$FAKE_GH_ROOT/$tag"
  signatures_dir="$BATS_TEST_TMPDIR/signatures"
  mkdir -p "$release_dir" "$signatures_dir"
  local filename
  for filename in "$prefix-linux-x64-cli.deb" "$prefix-win-x64-gui.msi" \
    "$prefix-osx-arm64-gui.dmg"; do
    echo "$filename" > "$release_dir/$filename"
  done
  echo '[{"tagName":"v2.4.1.0_stable_2026-10-29",
    "publishedAt":"2026-01-01T00:00:00Z"}]' > "$FAKE_GH_ROOT/releases.json"
}

# signs each file as <file>.sig and <file>.sig.asc in the release's zip, like
# duplicati's release builder.
zip_signatures() {
  local filename
  for filename in "$@"; do
    sign_detached signer "$release_dir/$filename" \
      "$signatures_dir/$filename.sig"
    cp "$signatures_dir/$filename.sig" "$signatures_dir/$filename.sig.asc"
  done
  echo C20E90473DAC703D > "$signatures_dir/sign-key.txt"
  (cd "$signatures_dir" && zip -q "$release_dir/$prefix.signatures.zip" ./*)
}

@test 'duplicati publishes each file signed in the signatures zip' {
  zip_signatures "$prefix-linux-x64-cli.deb" "$prefix-win-x64-gui.msi"
  run "$repo_dir/packages/duplicati/verify.sh"
  [ "$status" -eq 0 ]
  published_is "$prefix-linux-x64-cli.deb $prefix-win-x64-gui.msi"
  [ "$(state_of duplicati)" = '2026-01-01T00:00:00Z' ]
  [ -z "$(leftover_files duplicati)" ]
}

@test 'duplicati skips a file that does not match its signature' {
  zip_signatures "$prefix-linux-x64-cli.deb" "$prefix-win-x64-gui.msi"
  echo changed >> "$release_dir/$prefix-win-x64-gui.msi"
  run "$repo_dir/packages/duplicati/verify.sh"
  [ "$status" -eq 1 ]
  published_is "$prefix-linux-x64-cli.deb"
  [ "$(state_of duplicati)" = '2026-01-01T00:00:00Z' ]
}

@test 'duplicati skips an old release without a signatures zip' {
  run "$repo_dir/packages/duplicati/verify.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'signatures zip does not exist, skipping'* ]]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ "$(state_of duplicati)" = '2026-01-01T00:00:00Z' ]
}
