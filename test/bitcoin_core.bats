#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

# Writes a fake bitcoincore.org with releases 30.0 and 30.1, each with two files. 30.1 can be signed by another key
# or have a file changed after it was hashed.
make_site() {
  local root="$1"
  local release_30_1_signers="${2:-signer missing}"
  local is_release_30_1_tampered="${3:-false}"

  mkdir -p "$root/bitcoincore.org/en"
  cat > "$root/bitcoincore.org/en/releasesrss.xml" << 'EOF'
<rss><channel>
<item><title>Bitcoin Core 30.1</title><pubDate>Mon, 02 Feb 2026 00:00:00 +0000</pubDate></item>
<item><title>Bitcoin Core 30.0</title><pubDate>Thu, 01 Jan 2026 00:00:00 +0000</pubDate></item>
</channel></rss>
EOF

  local version
  for version in 30.0 30.1; do
    local bin_dir="$root/bitcoincore.org/bin/bitcoin-core-$version"
    mkdir -p "$bin_dir"
    cd "$bin_dir" || exit 1
    echo "core $version" > "bitcoin-$version.tar.gz"
    echo "core $version zip" > "bitcoin-$version.zip"
    shasum -a 256 "bitcoin-$version.tar.gz" "bitcoin-$version.zip" > SHA256SUMS

    local signers='signer missing'
    [ "$version" = 30.1 ] && signers="$release_30_1_signers"
    sign_detached "$signers" SHA256SUMS SHA256SUMS.asc
  done

  if [ "$is_release_30_1_tampered" = true ]; then
    echo 'changed' >> "$root/bitcoincore.org/bin/bitcoin-core-30.1/bitcoin-30.1.zip"
  fi
}

setup_file() {
  setup_keyring

  make_site "$BATS_FILE_TMPDIR/site"
  make_site "$BATS_FILE_TMPDIR/site-unlisted-signer" stranger
  make_site "$BATS_FILE_TMPDIR/site-tampered" 'signer missing' true
}

teardown_file() {
  teardown_keyring
}

setup() {
  create_repo bitcoin_core
  set_key_fingerprints bitcoin_core "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site"
  export FAKE_CURL_LOG="$BATS_TEST_TMPDIR/downloads"
}

downloaded_binaries() {
  grep -v SHA256SUMS "$FAKE_CURL_LOG" 2> /dev/null | sort | tr '\n' ' ' | sed 's/ $//'
}

@test 'publishes every file of every new release' {
  run "$repo_dir/packages/bitcoin_core/verify.sh"

  [ "$status" -eq 0 ]
  [ "$(published)" = 'bitcoin-30.0.tar.gz bitcoin-30.0.zip bitcoin-30.1.tar.gz bitcoin-30.1.zip' ]
  [ "$(state_of bitcoin_core)" = '2026-02-02T00:00:00+0000' ]
  [ -z "$(leftover_files bitcoin_core)" ]
}

@test 'downloads only the files that are not published yet' {
  run "$repo_dir/packages/bitcoin_core/verify.sh"
  rm "$XDG_CONFIG_HOME/verify-from-gpg/bitcoin_core" "$FAKE_CURL_LOG"
  grep -v -e 30.0.zip -e 30.1.tar.gz "$FAKE_NAK_LOG" > "$FAKE_NAK_LOG.new"
  mv "$FAKE_NAK_LOG.new" "$FAKE_NAK_LOG"

  run "$repo_dir/packages/bitcoin_core/verify.sh"

  [ "$status" -eq 0 ]
  [ "$(downloaded_binaries)" = 'bitcoin-30.0.zip bitcoin-30.1.tar.gz' ]
}

@test 'downloads no files from a release that is not signed by a listed key' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-unlisted-signer" run "$repo_dir/packages/bitcoin_core/verify.sh"

  [ "$status" -eq 0 ]
  [ "$(downloaded_binaries)" = 'bitcoin-30.0.tar.gz bitcoin-30.0.zip' ]
  [ "$(published)" = 'bitcoin-30.0.tar.gz bitcoin-30.0.zip' ]
}

@test 'does not publish a file that fails its hash check' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-tampered" run "$repo_dir/packages/bitcoin_core/verify.sh"

  [ "$status" -eq 0 ]
  [ "$(published)" = 'bitcoin-30.0.tar.gz bitcoin-30.0.zip bitcoin-30.1.tar.gz' ]
}

@test 'exits 1 when the release feed cannot be fetched' {
  FAKE_CURL_FAIL=releasesrss.xml run "$repo_dir/packages/bitcoin_core/verify.sh"

  [ "$status" -eq 1 ]
  [ -z "$(state_of bitcoin_core)" ]
}

@test 'exits without recording the release when a download fails' {
  FAKE_CURL_FAIL=bitcoin-30.1.zip run "$repo_dir/packages/bitcoin_core/verify.sh"

  [ "$status" -eq 1 ]
  [ "$(published)" = 'bitcoin-30.0.tar.gz bitcoin-30.0.zip bitcoin-30.1.tar.gz' ]
  [ "$(state_of bitcoin_core)" = '2026-01-01T00:00:00+0000' ]
  [ -z "$(leftover_files bitcoin_core)" ]
}
