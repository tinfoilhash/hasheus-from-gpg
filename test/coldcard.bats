#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

# Writes a fake coldcard.com whose downloads table links each row to a status page before the firmware, plus a
# signatures.txt on raw.githubusercontent.com signed by the given key.
make_site() {
  local root="$1"
  local signer="$2"

  local downloads_dir="$root/coldcard.com/downloads"
  mkdir -p "$downloads_dir" "$root/raw.githubusercontent.com/Coldcard/firmware/master/releases"

  cat > "$downloads_dir/all" << 'EOF'
<html><body><table><tbody>
<tr><td><a href="/security/status">[current fixed release]</a></td><td><a href="/downloads/2026-09-30T2026-v5.6.3-mk-coldcard.dfu">2026-09-30T2026-v5.6.3-mk-coldcard.dfu</a></td></tr>
<tr><td><a href="/security/status">[fixed]</a></td><td><a href="/downloads/2026-08-20T1336-v5.6.1-mk-coldcard.dfu">2026-08-20T1336-v5.6.1-mk-coldcard.dfu</a></td></tr>
<tr><td><a href="/security/status">[vulnerable]</a></td><td><a href="/docs/release-notes">release notes</a></td></tr>
</tbody></table></body></html>
EOF

  cd "$downloads_dir" || exit 1
  echo 'firmware 5.6.3' > 2026-09-30T2026-v5.6.3-mk-coldcard.dfu
  echo 'firmware 5.6.1' > 2026-08-20T1336-v5.6.1-mk-coldcard.dfu
  shasum -a 256 ./*.dfu | sed 's| \./| |' > "$root/hashes"
  sign_clear "$signer" "$root/hashes" "$root/raw.githubusercontent.com/Coldcard/firmware/master/releases/signatures.txt"
}

setup_file() {
  setup_keyring

  make_site "$BATS_FILE_TMPDIR/site" signer
  make_site "$BATS_FILE_TMPDIR/site-unlisted-signer" stranger

  # A site that lists firmware signatures.txt doesn't have yet.
  make_site "$BATS_FILE_TMPDIR/site-unsigned-firmware" signer
  local downloads_dir="$BATS_FILE_TMPDIR/site-unsigned-firmware/coldcard.com/downloads"
  sed -i.bak 's|<tbody>|<tbody><tr><td><a href="/downloads/2026-10-31T1200-v5.6.4-mk-coldcard.dfu">new</a></td></tr>|' "$downloads_dir/all"
  echo 'firmware 5.6.4' > "$downloads_dir/2026-10-31T1200-v5.6.4-mk-coldcard.dfu"

  # A site whose newest firmware changed after it was hashed.
  make_site "$BATS_FILE_TMPDIR/site-tampered" signer
  echo 'changed' >> "$BATS_FILE_TMPDIR/site-tampered/coldcard.com/downloads/2026-09-30T2026-v5.6.3-mk-coldcard.dfu"
}

teardown_file() {
  teardown_keyring
}

setup() {
  create_repo coldcard
  set_key_fingerprints coldcard "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site"
}

@test 'publishes firmware linked from rows that also link to a status page' {
  run "$repo_dir/packages/coldcard/verify.sh"

  [ "$status" -eq 0 ]
  [ "$(published)" = '2026-08-20T1336-v5.6.1-mk-coldcard.dfu 2026-09-30T2026-v5.6.3-mk-coldcard.dfu' ]
  [ "$(state_of coldcard)" = '2026-09-30T2026' ]
  [ -z "$(leftover_files coldcard)" ]
}

@test 'checks only firmware released since the last run' {
  set_state coldcard '2026-08-20T1336'

  run "$repo_dir/packages/coldcard/verify.sh"

  [ "$status" -eq 0 ]
  [ "$(published)" = '2026-09-30T2026-v5.6.3-mk-coldcard.dfu' ]
}

@test 'exits 1 when signatures.txt is not signed by a listed key' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-unlisted-signer" run "$repo_dir/packages/coldcard/verify.sh"

  [ "$status" -eq 1 ]
  [ -z "$(published)" ]
  [ -z "$(state_of coldcard)" ]
  [ -z "$(leftover_files coldcard)" ]
}

@test 'does not publish firmware that fails its hash check' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-tampered" run "$repo_dir/packages/coldcard/verify.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'file not verified, skipping'* ]]
  [ "$(published)" = '2026-08-20T1336-v5.6.1-mk-coldcard.dfu' ]
}

@test 'exits without recording firmware that signatures.txt does not have yet' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-unsigned-firmware" run "$repo_dir/packages/coldcard/verify.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"2026-10-31T1200-v5.6.4-mk-coldcard.dfu isn't in signatures.txt yet, exiting"* ]]
  [ "$(published)" = '2026-08-20T1336-v5.6.1-mk-coldcard.dfu 2026-09-30T2026-v5.6.3-mk-coldcard.dfu' ]
  [ "$(state_of coldcard)" = '2026-09-30T2026' ]
  [ -z "$(leftover_files coldcard)" ]
}

@test 'exits without recording the release when a download fails' {
  FAKE_CURL_FAIL=2026-09-30T2026-v5.6.3-mk-coldcard.dfu run "$repo_dir/packages/coldcard/verify.sh"

  [ "$status" -eq 1 ]
  [ "$(published)" = '2026-08-20T1336-v5.6.1-mk-coldcard.dfu' ]
  [ "$(state_of coldcard)" = '2026-08-20T1336' ]
  [ -z "$(leftover_files coldcard)" ]
}
