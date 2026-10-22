#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

FIRMWARE_5_6_1='2026-08-20T1336-v5.6.1-mk-coldcard.dfu'
FIRMWARE_5_6_3='2026-09-30T2026-v5.6.3-mk-coldcard.dfu'
FIRMWARE_5_6_4='2026-10-31T1200-v5.6.4-mk-coldcard.dfu'
SIGNATURES_PATH='raw.githubusercontent.com/Coldcard/firmware/master/releases'

# writes a fake coldcard.com whose downloads table links each row to a status
# page before the firmware, plus a signatures.txt on raw.githubusercontent.com
# signed by the given key.
make_site() {
  local root="$1"
  local signer="$2"

  local downloads_dir="$root/coldcard.com/downloads"
  mkdir -p "$downloads_dir" "$root/$SIGNATURES_PATH"

  cat > "$downloads_dir/all" << EOF
<html><body><table><tbody>
<tr>
<td><a href="/security/status">[current fixed release]</a></td>
<td><a href="/downloads/$FIRMWARE_5_6_3">$FIRMWARE_5_6_3</a></td>
</tr>
<tr>
<td><a href="/security/status">[fixed]</a></td>
<td><a href="/downloads/$FIRMWARE_5_6_1">$FIRMWARE_5_6_1</a></td>
</tr>
<tr>
<td><a href="/security/status">[vulnerable]</a></td>
<td><a href="/docs/release-notes">release notes</a></td>
</tr>
</tbody></table></body></html>
EOF

  cd "$downloads_dir" || exit 1
  echo 'firmware 5.6.3' > "$FIRMWARE_5_6_3"
  echo 'firmware 5.6.1' > "$FIRMWARE_5_6_1"
  shasum -a 256 ./*.dfu | sed 's| \./| |' > "$root/hashes"
  sign_clear "$signer" "$root/hashes" "$root/$SIGNATURES_PATH/signatures.txt"
}

setup_file() {
  setup_keyring

  make_site "$BATS_FILE_TMPDIR/site" signer
  make_site "$BATS_FILE_TMPDIR/site-unlisted-signer" stranger

  # a site that lists firmware signatures.txt doesn't have yet.
  local unsigned_root="$BATS_FILE_TMPDIR/site-unsigned-firmware"
  make_site "$unsigned_root" signer
  local unsigned_downloads_dir="$unsigned_root/coldcard.com/downloads"
  local row="<tr><td><a href=\"/downloads/$FIRMWARE_5_6_4\">new</a></td></tr>"
  sed -i.bak "s|<tbody>|<tbody>$row|" "$unsigned_downloads_dir/all"
  echo 'firmware 5.6.4' > "$unsigned_downloads_dir/$FIRMWARE_5_6_4"

  # a site whose newest firmware changed after it was hashed.
  local tampered_root="$BATS_FILE_TMPDIR/site-tampered"
  make_site "$tampered_root" signer
  echo 'changed' >> "$tampered_root/coldcard.com/downloads/$FIRMWARE_5_6_3"
}

teardown_file() {
  teardown_keyring
}

setup() {
  create_repo coldcard
  set_key_fingerprints coldcard "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site"
}

run_coldcard() {
  run "$repo_dir/packages/coldcard/verify.sh"
}

@test 'publishes firmware linked from rows that also link to a status page' {
  run_coldcard

  [ "$status" -eq 0 ]
  published_is "$FIRMWARE_5_6_1" "$FIRMWARE_5_6_3"
  [ "$(state_of coldcard)" = '2026-09-30T2026' ]
  [ -z "$(leftover_files coldcard)" ]
}

@test 'checks only firmware released since the last run' {
  set_state coldcard '2026-08-20T1336'

  run_coldcard

  [ "$status" -eq 0 ]
  published_is "$FIRMWARE_5_6_3"
}

@test 'exits 1 when signatures.txt is not signed by a listed key' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-unlisted-signer" run_coldcard

  [ "$status" -eq 1 ]
  [ -z "$(published)" ]
  [ -z "$(state_of coldcard)" ]
  [ -z "$(leftover_files coldcard)" ]
}

@test 'skips firmware that fails its hash, records, and exits 1' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-tampered" run_coldcard

  [ "$status" -eq 1 ]
  [[ "$output" == *"failed verification ($FIRMWARE_5_6_3), exiting"* ]]
  published_is "$FIRMWARE_5_6_1"
  [ "$(state_of coldcard)" = '2026-09-30T2026' ]
}

@test 'exits without recording firmware that signatures.txt does not have yet' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-unsigned-firmware" run_coldcard

  [ "$status" -eq 1 ]
  [[ "$output" == *"$FIRMWARE_5_6_4 isn't in signatures.txt yet, exiting"* ]]
  published_is "$FIRMWARE_5_6_1" "$FIRMWARE_5_6_3"
  [ "$(state_of coldcard)" = '2026-09-30T2026' ]
  [ -z "$(leftover_files coldcard)" ]
}

@test 'exits without recording the release when a download fails' {
  FAKE_CURL_FAIL="$FIRMWARE_5_6_3" run_coldcard

  [ "$status" -eq 1 ]
  published_is "$FIRMWARE_5_6_1"
  [ "$(state_of coldcard)" = '2026-08-20T1336' ]
  [ -z "$(leftover_files coldcard)" ]
}
