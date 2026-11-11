#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup_file() {
  setup_keyring
}

teardown_file() {
  teardown_keyring
}

write_ashigaru_page() {
  echo '<html><a id="top">top</a>' > "$site/index.html"
  local filename
  for filename in ashigaru_terminal_v1.0.0_amd64.deb \
    ashigaru_terminal_v1.0.0_windows.zip ashigaru_mobile_v1.2.0.apk; do
    echo "<a href=\"http://$onion/releases/$filename\">download</a>" \
      >> "$site/index.html"
  done
  local message
  for message in "$@"; do
    {
      echo '<pre><code>'
      cat "$message"
      echo '</code></pre>'
    } >> "$site/index.html"
  done
  echo '</html>' >> "$site/index.html"
}

setup() {
  create_repo ashigaru
  set_key_fingerprints ashigaru "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  export FAKE_CURL_PROXY_LOG="$BATS_TEST_TMPDIR/proxies"
  unset ASHIGARU_TOR_PROXY
  onion='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.onion'
  site="$FAKE_CURL_ROOT/ashigaru.rs/download"
  mkdir -p "$site" "$FAKE_CURL_ROOT/$onion/releases"
  local filename
  : > "$BATS_TEST_TMPDIR/terminal.txt"
  for filename in ashigaru_terminal_v1.0.0_amd64.deb \
    ashigaru_terminal_v1.0.0_windows.zip ashigaru_mobile_v1.2.0.apk; do
    echo "$filename" > "$FAKE_CURL_ROOT/$onion/releases/$filename"
    local hash
    hash=$(shasum -a 256 "$FAKE_CURL_ROOT/$onion/releases/$filename")
    if [[ "$filename" == ashigaru_terminal* ]]; then
      printf 'File name: %s\nSHA-256 Hash of file: %s\n\n' \
        "$filename" "${hash%% *}" >> "$BATS_TEST_TMPDIR/terminal.txt"
    else
      printf '%s\n\nSHA-256 Hash of the APK file:\n%s\n' \
        "$filename" "${hash%% *}" > "$BATS_TEST_TMPDIR/mobile.txt"
    fi
  done
  sign_clear signer "$BATS_TEST_TMPDIR/terminal.txt" \
    "$BATS_TEST_TMPDIR/terminal.asc"
  sign_clear signer "$BATS_TEST_TMPDIR/mobile.txt" \
    "$BATS_TEST_TMPDIR/mobile.asc"
  write_ashigaru_page "$BATS_TEST_TMPDIR/terminal.asc" \
    "$BATS_TEST_TMPDIR/mobile.asc"
}

@test 'ashigaru verifies terminal and mobile manifests over tor' {
  run "$repo_dir/packages/ashigaru/verify.sh"
  [ "$status" -eq 0 ]
  local expected='ashigaru_mobile_v1.2.0.apk'
  expected+=' ashigaru_terminal_v1.0.0_amd64.deb'
  expected+=' ashigaru_terminal_v1.0.0_windows.zip'
  published_is "$expected"
  [ "$(grep -c '^socks5h://127.0.0.1:9050 http:' \
    "$FAKE_CURL_PROXY_LOG")" = 3 ]
  [ -n "$(state_of ashigaru)" ]
}

@test 'ashigaru leaves a message with an unlisted signer pending' {
  sign_clear stranger "$BATS_TEST_TMPDIR/terminal.txt" \
    "$BATS_TEST_TMPDIR/terminal.asc"
  write_ashigaru_page "$BATS_TEST_TMPDIR/terminal.asc"
  run "$repo_dir/packages/ashigaru/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of ashigaru)" ]
}

@test 'ashigaru rejects unsafe filenames even with a valid signature' {
  printf 'File name: ../outside\nSHA-256 Hash of file: %064d\n' 0 \
    > "$BATS_TEST_TMPDIR/terminal.txt"
  sign_clear signer "$BATS_TEST_TMPDIR/terminal.txt" \
    "$BATS_TEST_TMPDIR/terminal.asc"
  write_ashigaru_page "$BATS_TEST_TMPDIR/terminal.asc"
  run "$repo_dir/packages/ashigaru/verify.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'invalid signed ashigaru filename'* ]]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of ashigaru)" ]
}

@test 'ashigaru refuses a proxy that could resolve onion dns locally' {
  export ASHIGARU_TOR_PROXY='socks5://127.0.0.1:9050'
  run "$repo_dir/packages/ashigaru/verify.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'tor proxy must use socks5h://'* ]]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
}
