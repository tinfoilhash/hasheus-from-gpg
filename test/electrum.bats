#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

# writes an apache-style index page, with the sorting and parent links apache
# adds, and a row for each name (with `=<modified time>` for a folder).
write_index() {
  local index_filename="$1"
  shift

  {
    echo '<html><body><table>'
    echo '<tr><th><a href="?C=N;O=D">Name</a></th></tr>'
    echo '<tr><td></td><td><a href="/">Parent Directory</a></td></tr>'

    local entry
    for entry in "$@"; do
      echo "<tr><td></td><td><a href=\"${entry%%=*}\">${entry%%=*}</a></td>"
      echo "<td align=\"right\">${entry#*=}  </td><td>-</td><td></td></tr>"
    done

    echo '</table></body></html>'
  } > "$index_filename"
}

# writes a version folder like electrum's: each file has a <file>.asc with
# every signer's signature (one from a key that isn't in the keyring first),
# a per-signer copy, and the source has an unsigned extra.
make_version() {
  local root="$1"
  local version="$2"
  local signer="${3:-signer}"

  local version_dir="$root/download.electrum.org/$version"
  mkdir -p "$version_dir"
  cd "$version_dir" || exit 1

  local filename
  for filename in "electrum-$version.dmg" "Electrum-$version.tar.gz"; do
    echo "$filename" > "$filename"
    sign_detached "missing $signer" "$filename" "$filename.asc"
    sign_detached "$signer" "$filename" "$filename.ThomasV.asc"
  done

  : > "Electrum-$version.tar.gz.f321x.asc"

  # list names bytewise, like apache, so the order doesn't depend on the locale.
  local LC_ALL=C
  local filenames=(*)
  write_index index.html "${filenames[@]}"
}

# writes a fake download.electrum.org with 4.8.1 and 4.8.2, plus folders that
# aren't versions.
make_site() {
  local root="$1"
  local signer="${2:-signer}"

  make_version "$root" 4.8.1 "$signer"
  make_version "$root" 4.8.2 "$signer"
  mkdir -p "$root/download.electrum.org/apk"

  write_index "$root/download.electrum.org/index.html" \
    '4.8.1/=2026-08-12 15:10' '4.8.2/=2026-09-12 18:10' \
    'apk/=2026-10-01 09:00'
}

setup_file() {
  setup_keyring

  make_site "$BATS_FILE_TMPDIR/site"
  make_site "$BATS_FILE_TMPDIR/site-unlisted-signer" stranger

  # a site whose newest version has no signatures yet.
  local unsigned_root="$BATS_FILE_TMPDIR/site-unsigned"
  make_site "$unsigned_root"
  cd "$unsigned_root/download.electrum.org/4.8.2" || exit 1
  rm ./*.asc index.html
  local LC_ALL=C
  local filenames=(*)
  write_index index.html "${filenames[@]}"

  # a site whose newest version folder serves a page that isn't an index.
  local not_index_root="$BATS_FILE_TMPDIR/site-not-index"
  make_site "$not_index_root"
  echo '<html><body>Just a moment...</body></html>' \
    > "$not_index_root/download.electrum.org/4.8.2/index.html"

  # a site whose newest dmg changed after it was signed.
  local tampered_root="$BATS_FILE_TMPDIR/site-tampered"
  make_site "$tampered_root"
  echo 'changed' \
    >> "$tampered_root/download.electrum.org/4.8.2/electrum-4.8.2.dmg"
}

teardown_file() {
  teardown_keyring
}

setup() {
  create_repo electrum
  set_key_fingerprints electrum "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site"
}

run_electrum() {
  run "$repo_dir/packages/electrum/verify.sh"
}

@test 'publishes each signed file in every version folder' {
  run_electrum

  [ "$status" -eq 0 ]
  published_is Electrum-4.8.1.tar.gz Electrum-4.8.2.tar.gz \
    electrum-4.8.1.dmg electrum-4.8.2.dmg
  [ "$(state_of electrum)" = '2026-09-12T18:10' ]
  [ -z "$(leftover_files electrum)" ]
}

@test 'checks only versions modified since the last run' {
  set_state electrum '2026-08-12T15:10'

  run_electrum

  [ "$status" -eq 0 ]
  published_is Electrum-4.8.2.tar.gz electrum-4.8.2.dmg
}

@test 'exits without recording a file not signed by a listed key' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-unlisted-signer" run_electrum

  [ "$status" -eq 1 ]
  [[ "$output" == *'file not verified, exiting'* ]]
  [ -z "$(published)" ]
  [ -z "$(state_of electrum)" ]
  [ -z "$(leftover_files electrum)" ]
}

@test 'exits without publishing or recording a file changed after signing' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-tampered" run_electrum

  [ "$status" -eq 1 ]
  [[ "$output" == *'file not verified, exiting'* ]]
  published_is Electrum-4.8.1.tar.gz Electrum-4.8.2.tar.gz \
    electrum-4.8.1.dmg
  [ "$(state_of electrum)" = '2026-08-12T15:10' ]
}

@test 'skips and records a version with no signed files' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-unsigned" run_electrum

  [ "$status" -eq 0 ]
  [[ "$output" == *'signed files do not exist, skipping'* ]]
  published_is Electrum-4.8.1.tar.gz electrum-4.8.1.dmg
  [ "$(state_of electrum)" = '2026-09-12T18:10' ]
}

@test 'exits without recording a version whose folder has no file links' {
  FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site-not-index" run_electrum

  [ "$status" -eq 1 ]
  [[ "$output" == *'no files in the folder listing, exiting'* ]]
  published_is Electrum-4.8.1.tar.gz electrum-4.8.1.dmg
  [ "$(state_of electrum)" = '2026-08-12T15:10' ]
  [ -z "$(leftover_files electrum)" ]
}

@test 'exits without recording the version when a download fails' {
  FAKE_CURL_FAIL=electrum-4.8.2.dmg run_electrum

  [ "$status" -eq 1 ]
  published_is Electrum-4.8.1.tar.gz Electrum-4.8.2.tar.gz \
    electrum-4.8.1.dmg
  [ "$(state_of electrum)" = '2026-08-12T15:10' ]
  [ -z "$(leftover_files electrum)" ]
}

@test 'skips files that are already published' {
  run_electrum
  rm "$XDG_CONFIG_HOME/hasheus-from-gpg/electrum"

  run_electrum

  [ "$status" -eq 0 ]
  [ "$(grep -c 'file already verified, skipping' <<< "$output")" -eq 4 ]
  [ "$(wc -l < "$FAKE_NAK_LOG")" -eq 4 ]
}
