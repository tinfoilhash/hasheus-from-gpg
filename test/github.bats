#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

# writes a release whose manifest has one detached signature per signer, like
# lnd. the first signature (by file name) is from a key that isn't in the
# keyring and the second from one that isn't listed. like lnd's, the manifest
# also lists a file from inside the archive that isn't a release asset.
make_release_with_signature_per_signer() {
  local release_dir="$1/$2"
  local tag="$2"

  mkdir -p "$release_dir/app-$tag"
  cd "$release_dir" || exit 1
  echo "app $tag" > "app-$tag.tar.gz"
  echo "app $tag binary" > "app-$tag/app"
  shasum -a 256 "app-$tag.tar.gz" "app-$tag/app" > "manifest-$tag.txt"
  rm -r "app-$tag"
  sign_detached missing "manifest-$tag.txt" "manifest-aaa-$tag.sig"
  sign_detached stranger "manifest-$tag.txt" "manifest-bbb-$tag.sig"
  sign_detached signer "manifest-$tag.txt" "manifest-zzz-$tag.sig"
}

# writes a release with a clearsigned manifest in binary mode (`*filename`),
# like wasabi.
make_release_with_clearsigned_manifest() {
  local release_dir="$1/$2"
  local tag="$2"
  local signer="${3:-signer}"

  mkdir -p "$release_dir"
  cd "$release_dir" || exit 1
  echo "app $tag" > "app-$tag.zip"
  shasum -a 256 -b "app-$tag.zip" > ../manifest
  sign_clear "$signer" ../manifest SHA256SUMS.asc
  rm ../manifest
}

# writes a release whose file names drop the tag's "v", like liana.
make_release_with_versioned_manifest() {
  local release_dir="$1/$2"
  local version="${2#v}"

  mkdir -p "$release_dir"
  cd "$release_dir" || exit 1
  echo "app $version" > "liana-$version.tar.gz"
  shasum -a 256 "liana-$version.tar.gz" > "liana-$version-shasums.txt"
  sign_detached signer \
    "liana-$version-shasums.txt" "liana-$version-shasums.txt.asc"
}

# writes a release that signs each file instead of a manifest, like trezor
# suite, with an unsigned file and a key attached as <id>.asc, like bisq's.
make_release_with_signed_files() {
  local release_dir="$1/$2"
  local tag="$2"
  local signer="${3:-signer}"

  mkdir -p "$release_dir"
  cd "$release_dir" || exit 1

  local filename
  for filename in "app-$tag.dmg" "app-$tag.exe"; do
    echo "$filename" > "$filename"
    sign_detached "$signer" "$filename" "$filename.asc"
  done

  echo "app $tag update metadata" > latest.yml
  gpg --armor --export signer@test > 1234ABCD.asc
}

write_releases() {
  local root="$1"
  shift

  local releases='[]'
  local release
  for release in "$@"; do
    releases=$(jaq -c \
      --arg tag "${release%%=*}" --arg published_at "${release#*=}" \
      '[{ tagName: $tag, publishedAt: $published_at }] + .' <<< "$releases")
  done

  echo "$releases" > "$root/releases.json"
}

setup_file() {
  setup_keyring

  local root="$BATS_FILE_TMPDIR"

  make_release_with_signature_per_signer "$root/per-signer/github.example" v1
  make_release_with_signature_per_signer "$root/per-signer/github.example" v2
  write_releases "$root/per-signer/github.example" v1=2026-01-01T00:00:00Z \
    v2=2026-02-01T00:00:00Z

  make_release_with_clearsigned_manifest "$root/clearsigned/github.example" v1
  make_release_with_clearsigned_manifest "$root/clearsigned/github.example" v2
  write_releases "$root/clearsigned/github.example" v1=2026-01-01T00:00:00Z \
    v2=2026-02-01T00:00:00Z

  make_release_with_versioned_manifest "$root/versioned/github.example" v1
  make_release_with_versioned_manifest "$root/versioned/github.example" v2
  write_releases "$root/versioned/github.example" v1=2026-01-01T00:00:00Z \
    v2=2026-02-01T00:00:00Z

  # a release with only an asset, one with hashes but no signature, and one
  # whose asset changed after it was hashed.
  mkdir -p "$root/no-hashes/github.example/v1"
  echo 'app v1' > "$root/no-hashes/github.example/v1/app-v1.zip"
  write_releases "$root/no-hashes/github.example" v1=2026-01-01T00:00:00Z

  make_release_with_signature_per_signer "$root/no-signature/github.example" v1
  rm "$root/no-signature/github.example/v1/"*.sig
  write_releases "$root/no-signature/github.example" v1=2026-01-01T00:00:00Z

  make_release_with_clearsigned_manifest "$root/tampered/github.example" v1
  echo 'changed' >> "$root/tampered/github.example/v1/app-v1.zip"
  write_releases "$root/tampered/github.example" v1=2026-01-01T00:00:00Z

  make_release_with_signed_files "$root/signed-files/github.example" v1
  make_release_with_signed_files "$root/signed-files/github.example" v2
  write_releases "$root/signed-files/github.example" v1=2026-01-01T00:00:00Z \
    v2=2026-02-01T00:00:00Z

  make_release_with_signed_files \
    "$root/signed-files-unlisted-signer/github.example" v1 stranger
  write_releases "$root/signed-files-unlisted-signer/github.example" \
    v1=2026-01-01T00:00:00Z

  make_release_with_signed_files "$root/signed-files-tampered/github.example" v1
  echo 'changed' >> "$root/signed-files-tampered/github.example/v1/app-v1.exe"
  write_releases "$root/signed-files-tampered/github.example" \
    v1=2026-01-01T00:00:00Z

  make_release_with_clearsigned_manifest \
    "$root/unlisted-signer/github.example" v1 stranger
  make_release_with_clearsigned_manifest \
    "$root/unlisted-signer/github.example" v2
  write_releases "$root/unlisted-signer/github.example" \
    v1=2026-01-01T00:00:00Z v2=2026-02-01T00:00:00Z
}

teardown_file() {
  teardown_keyring
}

setup() {
  create_repo
}

# writes a package script for the fake repo that lists the "other" and "signer"
# keys, followed by the shell code on stdin.
write_package_script() {
  mkdir -p "$repo_dir/packages/test"
  {
    cat << EOF
#!/usr/bin/env bash

package_dir=\$(dirname -- "\$(realpath "\$0")")
cd "\$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

package_name='test'
repo='fake/test'
key_fingerprints=(
  '$(fingerprint_of other)'
  '$(fingerprint_of signer)'
)
EOF
    cat
  } > "$repo_dir/packages/test/verify.sh"
  chmod +x "$repo_dir/packages/test/verify.sh"
}

# writes a package script with a signed manifest, plus any shell code (such as
# pattern functions) given on stdin.
write_package() {
  local shasum_filename_pattern="$1"
  local shasum_signature_filename_pattern="$2"

  {
    cat
    cat << EOF
verify_from_github "\$package_name" "\$repo" \\
  '$shasum_filename_pattern' '$shasum_signature_filename_pattern' \\
  "\${key_fingerprints[@]}"
EOF
  } | write_package_script
}

# writes a package script with a signature for each file, like trezor suite.
write_signed_files_package() {
  write_package_script << 'EOF'
verify_signed_files_from_github "$package_name" "$repo" .asc \
  "${key_fingerprints[@]}"
EOF
}

# serves a fixture's releases through the fake gh, and their assets through the
# fake curl.
run_package() {
  export FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/$1"
  export FAKE_GH_ROOT="$FAKE_CURL_ROOT/github.example"
  run "$repo_dir/packages/test/verify.sh"
}

@test 'publishes every release when each signer has their own signature file' {
  write_package 'manifest-{{NAME}}.txt' 'manifest-*-{{NAME}}.sig' < /dev/null

  run_package per-signer

  [ "$status" -eq 0 ]
  [ "$(published)" = 'app-v1.tar.gz app-v2.tar.gz' ]
  [ "$(state_of test)" = '2026-02-01T00:00:00Z' ]
  [ -z "$(leftover_files test)" ]
}

@test 'skips manifest entries that are not release assets' {
  write_package 'manifest-{{NAME}}.txt' 'manifest-*-{{NAME}}.sig' < /dev/null

  run_package per-signer

  [ "$status" -eq 0 ]
  [ "$(grep -c 'file is not a release asset, skipping' <<< "$output")" -eq 2 ]
}

@test 'downloads only hashes, signatures, and files not published yet' {
  write_package 'manifest-{{NAME}}.txt' 'manifest-*-{{NAME}}.sig' < /dev/null
  run_package per-signer
  rm "$XDG_CONFIG_HOME/verify-from-gpg/test"
  grep -v app-v2.tar.gz "$FAKE_NAK_LOG" > "$FAKE_NAK_LOG.new"
  mv "$FAKE_NAK_LOG.new" "$FAKE_NAK_LOG"
  local downloads="$BATS_TEST_TMPDIR/downloads"

  FAKE_CURL_LOG="$downloads" run_package per-signer

  [ "$status" -eq 0 ]
  [ "$(grep -v -e '^manifest-' "$downloads")" = 'app-v2.tar.gz' ]
  [ "$(grep -c '^manifest-' "$downloads")" -eq 8 ]
}

@test 'publishes clearsigned manifests that use binary mode file names' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null

  run_package clearsigned

  [ "$status" -eq 0 ]
  [ "$(published)" = 'app-v1.zip app-v2.zip' ]
}

@test 'resolves pattern functions for every release' {
  write_package shasum_filename_pattern \
    shasum_signature_filename_pattern << 'EOF'
shasum_filename_pattern() { echo "liana-${1#v}-shasums.txt"; }
shasum_signature_filename_pattern() { echo "liana-${1#v}-shasums.txt.asc"; }
EOF

  run_package versioned

  [ "$status" -eq 0 ]
  [ "$(published)" = 'liana-1.tar.gz liana-2.tar.gz' ]
}

@test 'exits without recording a release that is not signed by a listed key' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null

  run_package unlisted-signer

  [ "$status" -eq 1 ]
  [[ "$output" == *'gpg signatures verification failed, exiting'* ]]
  [ -z "$(published)" ]
  [ -z "$(state_of test)" ]
  [ -z "$(leftover_files test)" ]
}

@test 'skips and records a release with no hashes file' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null

  run_package no-hashes

  [ "$status" -eq 0 ]
  [[ "$output" == *'hashes file does not exist, skipping'* ]]
  [ -z "$(published)" ]
  [ "$(state_of test)" = '2026-01-01T00:00:00Z' ]
}

@test 'skips and records a release with no signature file' {
  write_package 'manifest-{{NAME}}.txt' 'manifest-*-{{NAME}}.sig' < /dev/null

  run_package no-signature

  [ "$status" -eq 0 ]
  [[ "$output" == *'gpg signatures file does not exist, skipping'* ]]
  [ -z "$(published)" ]
  [ "$(state_of test)" = '2026-01-01T00:00:00Z' ]
}

@test 'exits without publishing or recording a file that fails its hash check' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null

  run_package tampered

  [ "$status" -eq 1 ]
  [[ "$output" == *'file not verified, exiting'* ]]
  [ -z "$(published)" ]
  [ -z "$(state_of test)" ]
}

@test 'checks only releases published since the last run' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null
  set_state test '2026-01-01T00:00:00Z'

  run_package clearsigned

  [ "$status" -eq 0 ]
  [ "$(published)" = 'app-v2.zip' ]
}

@test 'exits without recording a failed publish, and a rerun publishes it' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null

  FAKE_NAK_FAIL=app-v1.zip run_package clearsigned

  [ "$status" -eq 1 ]
  [ -z "$(published)" ]
  [ -z "$(state_of test)" ]
  [ -z "$(leftover_files test)" ]

  run_package clearsigned

  [ "$status" -eq 0 ]
  [ "$(published)" = 'app-v1.zip app-v2.zip' ]
}

@test 'exits without recording the release when a download fails' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null

  FAKE_CURL_FAIL=app-v2.zip run_package clearsigned

  [ "$status" -eq 1 ]
  [ "$(published)" = 'app-v1.zip' ]
  [ "$(state_of test)" = '2026-01-01T00:00:00Z' ]
  [ -z "$(leftover_files test)" ]
}

@test 'retries a relay query that fails instead of republishing' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null
  run_package clearsigned
  rm "$XDG_CONFIG_HOME/verify-from-gpg/test"
  local failures="$BATS_TEST_TMPDIR/failures"
  echo 2 > "$failures"

  FAKE_NAK_REQ_FAILURES="$failures" run_package clearsigned

  [ "$status" -eq 0 ]
  [ "$(grep -c 'relay query failed (attempt' <<< "$output")" -eq 2 ]
  [ "$(published)" = 'app-v1.zip app-v2.zip' ]
}

@test 'retries a publish that fails instead of stopping' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null
  local failures="$BATS_TEST_TMPDIR/failures"
  echo 2 > "$failures"

  FAKE_NAK_EVENT_FAILURES="$failures" run_package clearsigned

  [ "$status" -eq 0 ]
  [ "$(grep -c 'publish failed (attempt' <<< "$output")" -eq 2 ]
  published_is app-v1.zip app-v2.zip
  [ "$(state_of test)" = '2026-02-01T00:00:00Z' ]
}

@test 'does not republish a failed publish that reached the relay' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null
  local failures="$BATS_TEST_TMPDIR/failures"
  echo 1 > "$failures"

  FAKE_NAK_EVENT_FAILURES="$failures" FAKE_NAK_EVENT_LANDS=1 \
    run_package clearsigned

  [ "$status" -eq 0 ]
  [[ "$output" == *'event was published after all'* ]]
  [ "$(wc -l < "$FAKE_NAK_LOG")" -eq 2 ]
}

@test 'exits without recording after three failed publishes' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null
  local failures="$BATS_TEST_TMPDIR/failures"
  echo 3 > "$failures"

  FAKE_NAK_EVENT_FAILURES="$failures" run_package clearsigned

  [ "$status" -eq 1 ]
  [ "$(grep -c 'publish failed (attempt' <<< "$output")" -eq 3 ]
  [[ "$output" == *'publish failed, exiting'* ]]
  [ -z "$(published)" ]
  [ -z "$(state_of test)" ]
}

@test 'exits instead of publishing when the relay cannot be queried' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null
  local failures="$BATS_TEST_TMPDIR/failures"
  echo 3 > "$failures"

  FAKE_NAK_REQ_FAILURES="$failures" run_package clearsigned

  [ "$status" -eq 1 ]
  [[ "$output" == *'relay query failed, exiting'* ]]
  [ -z "$(published)" ]
  [ -z "$(state_of test)" ]
}

@test 'publishes and records nothing in a dry run with only an npub' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null
  unset NSEC

  local npub='npub1gm7yl6a9xsnkg2lepuaf4hddv2yvwlun5atxjtye3pu5l0vh5kes8ef4r5'

  DRY_RUN=1 NPUB="$npub" run_package clearsigned

  [ "$status" -eq 0 ]
  [[ "$output" == *'dry run: would publish app-v1.zip'* ]]
  [[ "$output" == *'dry run: would publish app-v2.zip'* ]]
  [ -z "$(published)" ]
  [ -z "$(state_of test)" ]
  [ -z "$(leftover_files test)" ]
}

@test 'skips files that are already published' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null
  run_package clearsigned
  rm "$XDG_CONFIG_HOME/verify-from-gpg/test"

  run_package clearsigned

  [ "$status" -eq 0 ]
  [ "$(grep -c 'file already verified, skipping' <<< "$output")" -eq 2 ]
  [ "$(wc -l < "$FAKE_NAK_LOG")" -eq 2 ]
}

@test 'publishes each file that has its own signature' {
  write_signed_files_package

  run_package signed-files

  [ "$status" -eq 0 ]
  published_is app-v1.dmg app-v1.exe app-v2.dmg app-v2.exe
  [ "$(state_of test)" = '2026-02-01T00:00:00Z' ]
  [ -z "$(leftover_files test)" ]
}

@test 'skips and records a release with no signed files' {
  write_signed_files_package

  run_package no-hashes

  [ "$status" -eq 0 ]
  [[ "$output" == *'signed files do not exist, skipping'* ]]
  [ -z "$(published)" ]
  [ "$(state_of test)" = '2026-01-01T00:00:00Z' ]
}

@test 'exits without recording a file not signed by a listed key' {
  write_signed_files_package

  run_package signed-files-unlisted-signer

  [ "$status" -eq 1 ]
  [[ "$output" == *'file not verified, exiting'* ]]
  [ -z "$(published)" ]
  [ -z "$(state_of test)" ]
  [ -z "$(leftover_files test)" ]
}

@test 'exits without publishing or recording a file changed after signing' {
  write_signed_files_package

  run_package signed-files-tampered

  [ "$status" -eq 1 ]
  [[ "$output" == *'file not verified, exiting'* ]]
  published_is app-v1.dmg
  [ -z "$(state_of test)" ]
}

@test 'exits without recording the release when a signed file download fails' {
  write_signed_files_package

  FAKE_CURL_FAIL=app-v2.exe run_package signed-files

  [ "$status" -eq 1 ]
  published_is app-v1.dmg app-v1.exe app-v2.dmg
  [ "$(state_of test)" = '2026-01-01T00:00:00Z' ]
  [ -z "$(leftover_files test)" ]
}

@test 'skips signed files already published without downloading them' {
  write_signed_files_package
  run_package signed-files
  rm "$XDG_CONFIG_HOME/verify-from-gpg/test"
  local downloads="$BATS_TEST_TMPDIR/downloads"

  FAKE_CURL_LOG="$downloads" run_package signed-files

  [ "$status" -eq 0 ]
  [ "$(grep -c 'file already verified, skipping' <<< "$output")" -eq 4 ]
  [ ! -s "$downloads" ]
  [ "$(wc -l < "$FAKE_NAK_LOG")" -eq 4 ]
}

@test 'skips signed files already published when github has no digests' {
  export FAKE_GH_NO_DIGESTS=1
  write_signed_files_package
  run_package signed-files
  rm "$XDG_CONFIG_HOME/verify-from-gpg/test"
  local downloads="$BATS_TEST_TMPDIR/downloads"

  FAKE_CURL_LOG="$downloads" run_package signed-files

  [ "$status" -eq 0 ]
  [ "$(grep -c 'file already verified, skipping' <<< "$output")" -eq 4 ]
  [ "$(grep -c -v '\.asc$' "$downloads")" -eq 4 ]
  [ "$(wc -l < "$FAKE_NAK_LOG")" -eq 4 ]
}
