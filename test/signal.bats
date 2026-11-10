#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

make_site() {
  local root="$1"
  local latest_signer="${2:-signer}"

  mkdir -p "$root/github.example" "$root/updates.signal.org/desktop"
  cat > "$root/github.example/releases.json" << 'EOF'
[
  {"tagName":"v8.35.0-beta.1","publishedAt":"2026-11-05T16:08:27Z"},
  {"tagName":"v8.34.0","publishedAt":"2026-11-05T15:31:49Z"},
  {"tagName":"v8.33.0","publishedAt":"2026-10-28T22:17:52Z"}
]
EOF

  cd "$root/updates.signal.org/desktop" || exit 1

  local version signer filename
  for version in 8.33.0 8.34.0; do
    signer='signer'
    [ "$version" = 8.34.0 ] && signer="$latest_signer"
    filename="signal-desktop_${version}_x86_64.AppImage"
    echo "$filename" > "$filename"
    sign_detached "$signer" "$filename" "$filename.gpg"
  done
}

setup_file() {
  setup_keyring

  make_site "$BATS_FILE_TMPDIR/site"
  make_site "$BATS_FILE_TMPDIR/site-unlisted-signer" stranger
  local root="$BATS_FILE_TMPDIR/site-tampered"
  make_site "$root"
  echo 'changed' \
    >> "$root/updates.signal.org/desktop/signal-desktop_8.34.0_x86_64.AppImage"
}

teardown_file() {
  teardown_keyring
}

setup() {
  create_repo signal
  set_key_fingerprints signal "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site"
  export FAKE_GH_ROOT="$FAKE_CURL_ROOT/github.example"
}

run_signal() {
  run "$repo_dir/packages/signal/verify.sh"
}

@test 'publishes versioned stable appimages and ignores beta releases' {
  run_signal

  [ "$status" -eq 0 ]
  published_is signal-desktop_8.33.0_x86_64.AppImage \
    signal-desktop_8.34.0_x86_64.AppImage
  local url='https://updates.signal.org/desktop'
  [[ "$output" == *"url: $url/signal-desktop_8.34.0_x86_64.AppImage"* ]]
  [ "$(state_of signal)" = '2026-11-05T15:31:49Z' ]
  [ -z "$(leftover_files signal)" ]
}

@test 'checks only releases newer than the recorded state' {
  set_state signal '2026-10-28T22:17:52Z'

  run_signal

  [ "$status" -eq 0 ]
  published_is signal-desktop_8.34.0_x86_64.AppImage
}

@test 'does nothing when there are no new stable releases' {
  set_state signal '2026-11-05T15:31:49Z'

  run_signal

  [ "$status" -eq 0 ]
  [ -z "$(published)" ]
  [ "$(state_of signal)" = '2026-11-05T15:31:49Z' ]
}

@test 'does not record an appimage signed by an unlisted key' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-unlisted-signer" run_signal

  [ "$status" -eq 1 ]
  [[ "$output" == *'file not verified, exiting'* ]]
  published_is signal-desktop_8.33.0_x86_64.AppImage
  [ "$(state_of signal)" = '2026-10-28T22:17:52Z' ]
  [ -z "$(leftover_files signal)" ]
}

@test 'skips a changed appimage, records its release, and exits 1' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-tampered" run_signal

  [ "$status" -eq 1 ]
  [[ "$output" == *'file not verified, skipping'* ]]
  published_is signal-desktop_8.33.0_x86_64.AppImage
  [ "$(state_of signal)" = '2026-11-05T15:31:49Z' ]
  [ -z "$(leftover_files signal)" ]
}

@test 'does not record a release when its signature cannot be downloaded' {
  FAKE_CURL_FAIL=signal-desktop_8.34.0_x86_64.AppImage.gpg run_signal

  [ "$status" -eq 1 ]
  published_is signal-desktop_8.33.0_x86_64.AppImage
  [ "$(state_of signal)" = '2026-10-28T22:17:52Z' ]
  [ -z "$(leftover_files signal)" ]
}

@test 'does not record a release when its appimage cannot be downloaded' {
  FAKE_CURL_FAIL=signal-desktop_8.34.0_x86_64.AppImage run_signal

  [ "$status" -eq 1 ]
  published_is signal-desktop_8.33.0_x86_64.AppImage
  [ "$(state_of signal)" = '2026-10-28T22:17:52Z' ]
  [ -z "$(leftover_files signal)" ]
}

@test 'exits without recording state when release discovery fails' {
  FAKE_GH_ROOT="$BATS_TEST_TMPDIR/missing" run_signal

  [ "$status" -eq 1 ]
  [ -z "$(published)" ]
  [ -z "$(state_of signal)" ]
}

@test 'ignores unsafe release names instead of using them in a url' {
  mkdir -p "$BATS_TEST_TMPDIR/github.example"
  cat > "$BATS_TEST_TMPDIR/github.example/releases.json" << 'EOF'
[{
  "tagName":"v8.34.0/../../unexpected",
  "publishedAt":"2026-11-05T15:31:49Z"
}]
EOF

  FAKE_GH_ROOT="$BATS_TEST_TMPDIR/github.example" run_signal

  [ "$status" -eq 0 ]
  [ -z "$(published)" ]
  [ -z "$(state_of signal)" ]
}

@test 'rejects an invalid release date before publishing' {
  mkdir -p "$BATS_TEST_TMPDIR/github.example"
  cat > "$BATS_TEST_TMPDIR/github.example/releases.json" << 'EOF'
[{"tagName":"v8.34.0","publishedAt":"not-a-date"}]
EOF

  FAKE_GH_ROOT="$BATS_TEST_TMPDIR/github.example" run_signal

  [ "$status" -eq 1 ]
  [[ "$output" == *'invalid release date'* ]]
  [ -z "$(published)" ]
  [ -z "$(state_of signal)" ]
}

@test 'skips appimages that have already been published' {
  run_signal
  rm "$XDG_CONFIG_HOME/hasheus-from-gpg/signal"

  run_signal

  [ "$status" -eq 0 ]
  [ "$(grep -c 'file already verified, skipping' <<< "$output")" -eq 2 ]
  [ "$(wc -l < "$FAKE_HASHEUS_LOG")" -eq 2 ]
}

@test 'a dry run neither publishes nor records releases' {
  DRY_RUN=1 run_signal

  [ "$status" -eq 0 ]
  [[ "$output" == *'verified: yes'* ]]
  [[ "$output" == *'dry run: would record 2026-11-05T15:31:49Z'* ]]
  [ -z "$(published)" ]
  [ -z "$(state_of signal)" ]
  [ -z "$(leftover_files signal)" ]
}
