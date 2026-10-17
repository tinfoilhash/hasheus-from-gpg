#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

# Writes a release whose manifest has one detached signature per signer, like lnd. The first signature (by file
# name) is from a key that isn't in the keyring and the second from one that isn't listed.
make_release_with_signature_per_signer() {
  local release_dir="$1/$2"
  local tag="$2"

  mkdir -p "$release_dir"
  cd "$release_dir" || exit 1
  echo "app $tag" > "app-$tag.tar.gz"
  shasum -a 256 "app-$tag.tar.gz" > "manifest-$tag.txt"
  sign_detached missing "manifest-$tag.txt" "manifest-aaa-$tag.sig"
  sign_detached stranger "manifest-$tag.txt" "manifest-bbb-$tag.sig"
  sign_detached signer "manifest-$tag.txt" "manifest-zzz-$tag.sig"
}

# Writes a release with a clearsigned manifest in binary mode (`*filename`), like wasabi.
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

# Writes a release whose file names drop the tag's "v", like liana.
make_release_with_versioned_manifest() {
  local release_dir="$1/$2"
  local version="${2#v}"

  mkdir -p "$release_dir"
  cd "$release_dir" || exit 1
  echo "app $version" > "liana-$version.tar.gz"
  shasum -a 256 "liana-$version.tar.gz" > "liana-$version-shasums.txt"
  sign_detached signer "liana-$version-shasums.txt" "liana-$version-shasums.txt.asc"
}

write_releases() {
  local root="$1"
  shift

  local releases='[]'
  local release
  for release in "$@"; do
    releases=$(jaq -c --arg tag "${release%%=*}" --arg published_at "${release#*=}" \
      '[{ tagName: $tag, publishedAt: $published_at }] + .' <<< "$releases")
  done

  echo "$releases" > "$root/releases.json"
}

setup_file() {
  setup_keyring

  local root="$BATS_FILE_TMPDIR"

  make_release_with_signature_per_signer "$root/per-signer" v1
  make_release_with_signature_per_signer "$root/per-signer" v2
  write_releases "$root/per-signer" v1=2026-01-01T00:00:00Z v2=2026-02-01T00:00:00Z

  make_release_with_clearsigned_manifest "$root/clearsigned" v1
  make_release_with_clearsigned_manifest "$root/clearsigned" v2
  write_releases "$root/clearsigned" v1=2026-01-01T00:00:00Z v2=2026-02-01T00:00:00Z

  make_release_with_versioned_manifest "$root/versioned" v1
  make_release_with_versioned_manifest "$root/versioned" v2
  write_releases "$root/versioned" v1=2026-01-01T00:00:00Z v2=2026-02-01T00:00:00Z

  make_release_with_clearsigned_manifest "$root/unlisted-signer" v1 stranger
  make_release_with_clearsigned_manifest "$root/unlisted-signer" v2
  write_releases "$root/unlisted-signer" v1=2026-01-01T00:00:00Z v2=2026-02-01T00:00:00Z
}

teardown_file() {
  teardown_keyring
}

setup() {
  create_repo
}

# Writes a package script for the fake repo, plus any shell code (such as pattern functions) given on stdin.
write_package() {
  local shasum_filename_pattern="$1"
  local shasum_signature_filename_pattern="$2"

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
shasum_filename_pattern='$shasum_filename_pattern'
shasum_signature_filename_pattern='$shasum_signature_filename_pattern'
EOF
    cat
    echo 'verify_from_github "$package_name" "$repo" "$shasum_filename_pattern" "$shasum_signature_filename_pattern" "${key_fingerprints[@]}"'
  } > "$repo_dir/packages/test/verify.sh"
  chmod +x "$repo_dir/packages/test/verify.sh"
}

run_package() {
  export FAKE_GH_ROOT="$BATS_FILE_TMPDIR/$1"
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

@test 'publishes clearsigned manifests that use binary mode file names' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null

  run_package clearsigned

  [ "$status" -eq 0 ]
  [ "$(published)" = 'app-v1.zip app-v2.zip' ]
}

@test 'resolves pattern functions for every release' {
  write_package shasum_filename_pattern shasum_signature_filename_pattern << 'EOF'
shasum_filename_pattern() { echo "liana-${1#v}-shasums.txt"; }
shasum_signature_filename_pattern() { echo "liana-${1#v}-shasums.txt.asc"; }
EOF

  run_package versioned

  [ "$status" -eq 0 ]
  [ "$(published)" = 'liana-1.tar.gz liana-2.tar.gz' ]
}

@test 'skips and records a release that is not signed by a listed key' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null

  run_package unlisted-signer

  [ "$status" -eq 0 ]
  [[ "$output" == *'gpg signatures verification failed, skipping'* ]]
  [ "$(published)" = 'app-v2.zip' ]
  [ "$(state_of test)" = '2026-02-01T00:00:00Z' ]
}

@test 'checks only releases published since the last run' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null
  set_state test '2026-01-01T00:00:00Z'

  run_package clearsigned

  [ "$status" -eq 0 ]
  [ "$(published)" = 'app-v2.zip' ]
}

@test 'exits without recording the release when publishing fails, and a rerun publishes the rest' {
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

  FAKE_GH_DOWNLOAD_FAIL=v2 run_package clearsigned

  [ "$status" -eq 1 ]
  [ "$(published)" = 'app-v1.zip' ]
  [ "$(state_of test)" = '2026-01-01T00:00:00Z' ]
  [ -z "$(leftover_files test)" ]
}

@test 'publishes and records nothing in a dry run' {
  write_package 'SHA256SUMS.asc' 'SHA256SUMS.asc' < /dev/null

  DRY_RUN=1 run_package clearsigned

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
