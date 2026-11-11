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
  create_repo startos
  set_key_fingerprints startos "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  export FAKE_GH_ROOT="$BATS_TEST_TMPDIR/gh"
  mkdir -p "$FAKE_GH_ROOT/api/repos/Start9Labs/start-technologies"
  local api="$FAKE_GH_ROOT/api/repos/Start9Labs/start-technologies/releases"
  jaq -n '[range(0;100) | {tag_name: ("start-sdk/v" + tostring),
    published_at: "2026-10-07T00:16:00Z", draft: false}]' \
    > "$api?per_page=100&page=1.json"
  echo '[{"tag_name":"start-os/v0.4.2",
    "published_at":"2026-10-06T00:16:00Z","draft":false}]' \
    > "$api?per_page=100&page=2.json"
  local assets="$FAKE_GH_ROOT/start-os/v0.4.2"
  mkdir -p "$assets" "$BATS_TEST_TMPDIR/signatures"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  mkdir -p "$FAKE_CURL_ROOT/github.example/start-os"
  ln -s "$assets" "$FAKE_CURL_ROOT/github.example/start-os/v0.4.2"
  local filename
  for filename in startos-0.4.2-abc_x86_64.iso \
    startos-0.4.2-abc_raspberrypi.img.gz \
    startos-0.4.2-abc_aarch64.squashfs; do
    local dir="$FAKE_CURL_ROOT/startos-images.nyc3.cdn.digitaloceanspaces.com"
    dir+='/v0.4.2'
    mkdir -p "$dir"
    echo "$filename" > "$dir/$filename"
    local signer
    for signer in signer stranger; do
      gpg_quiet --armor -u "$signer@test" --detach-sign \
        -o "$BATS_TEST_TMPDIR/signatures/$filename.$signer.asc" \
        "$dir/$filename"
    done
  done
  tar -czf "$assets/signatures.tar.gz" -C "$BATS_TEST_TMPDIR/signatures" .
}

@test 'startos filters sdk tags before limiting os releases' {
  run "$repo_dir/packages/startos/verify.sh"
  [ "$status" -eq 0 ]
  local expected='startos-0.4.2-abc_aarch64.squashfs'
  expected+=' startos-0.4.2-abc_raspberrypi.img.gz'
  expected+=' startos-0.4.2-abc_x86_64.iso'
  published_is "$expected"
  [ "$(state_of startos)" = '2026-10-06T00:16:00Z' ]
  [ -z "$(leftover_files startos)" ]
}

@test 'startos rejects archive links before downloading any image' {
  ln -s /tmp/outside "$BATS_TEST_TMPDIR/signatures/unsafe.asc"
  tar -czf "$FAKE_GH_ROOT/start-os/v0.4.2/signatures.tar.gz" \
    -C "$BATS_TEST_TMPDIR/signatures" .
  run "$repo_dir/packages/startos/verify.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'link or special file'* ]]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of startos)" ]
}

@test 'startos rejects nested archive paths without extracting them' {
  mkdir "$BATS_TEST_TMPDIR/signatures/nested"
  echo bad > "$BATS_TEST_TMPDIR/signatures/nested/file.asc"
  tar -czf "$FAKE_GH_ROOT/start-os/v0.4.2/signatures.tar.gz" \
    -C "$BATS_TEST_TMPDIR/signatures" .
  run "$repo_dir/packages/startos/verify.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'unsafe signature archive member'* ]]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of startos)" ]
}

@test 'startos retries when no image signature uses a listed key' {
  rm "$BATS_TEST_TMPDIR/signatures/"*.signer.asc
  tar -czf "$FAKE_GH_ROOT/start-os/v0.4.2/signatures.tar.gz" \
    -C "$BATS_TEST_TMPDIR/signatures" .
  run "$repo_dir/packages/startos/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of startos)" ]
}
