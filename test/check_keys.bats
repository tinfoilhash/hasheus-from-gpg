#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

REPO_PATH='raw.githubusercontent.com/owner/keys/main'
REPO_URL="https://$REPO_PATH"
KEYS_URL="$REPO_URL/keys"
ALL_KEYS=(signer=signer.asc expired=expired.asc stranger=stranger.asc
  missing=missing.asc)

# runs gpg as if it were the start of 2020, to make keys that have expired.
gpg_in_2020() {
  gpg_quiet --faked-system-time 20200101T000000! "$@"
}

setup_file() {
  setup_keyring

  # an expired key, made by pretending it's 2020.
  gpg_in_2020 --quick-gen-key expired@test ed25519 sign 1y

  # a revoked key, using the revocation certificate gpg saves when it makes a
  # key.
  gpg_quiet --quick-gen-key revoked@test ed25519 sign never
  sed 's/^:-----/-----/' \
    "$GNUPGHOME/openpgp-revocs.d/$(fingerprint_of revoked).rev" \
    | gpg_quiet --import

  # a key whose only signing subkey expired, made by pretending it's 2020.
  gpg_in_2020 --quick-gen-key no-signing-key@test ed25519 cert never
  gpg_in_2020 \
    --quick-add-key "$(fingerprint_of no-signing-key)" ed25519 sign 1y

  # a key that's only in the missing keyring, to be offered alongside "missing"
  # in one file.
  GNUPGHOME="$MISSING_GNUPGHOME" gpg_quiet \
    --quick-gen-key unwanted@test ed25519 sign never

  local site_repo="$BATS_FILE_TMPDIR/site/$REPO_PATH"
  local keys_dir="$site_repo/keys"
  mkdir -p "$keys_dir"

  gpg --armor --export signer@test > "$keys_dir/signer.asc"
  gpg --armor --export signer@test > "$keys_dir/signer-alias.asc"
  gpg --armor --export expired@test > "$keys_dir/expired.asc"
  gpg --armor --export stranger@test > "$keys_dir/stranger.asc"
  GNUPGHOME="$MISSING_GNUPGHOME" gpg --armor \
    --export missing@test unwanted@test > "$keys_dir/missing.asc"

  # keys at the repo's root, outside the key folder.
  gpg --armor --export signer@test > "$site_repo/signer.asc"
  gpg --armor --export revoked@test > "$site_repo/revoked.asc"
  gpg --armor --export no-signing-key@test > "$site_repo/no-signing-key.asc"

  # a keyserver lookup, which has no file name.
  local lookup
  lookup="lookup?op=get&search=0x$(fingerprint_of signer)"
  mkdir -p "$BATS_FILE_TMPDIR/site/keyserver.example/pks"
  gpg --armor --export signer@test \
    > "$BATS_FILE_TMPDIR/site/keyserver.example/pks/$lookup"

  # the key folder's listing, as github's contents api returns it.
  local listing_dir="$BATS_FILE_TMPDIR/api/repos/owner/keys/contents"
  mkdir -p "$listing_dir"
  local path
  for path in "$keys_dir"/*.asc; do
    jaq -n --arg name "${path##*/}" --arg url "$KEYS_URL/${path##*/}" \
      '{ type: "file", name: $name, download_url: $url }'
  done | jaq -s '. + [{ type: "file", name: "README.md", download_url: "" }]' \
    > "$listing_dir/keys.json"
}

teardown_file() {
  teardown_keyring
}

setup() {
  create_repo
  cp "$PROJECT_DIR/check_keys.sh" "$repo_dir/"
  export FAKE_CURL_ROOT="$BATS_FILE_TMPDIR/site"
  export FAKE_GH_ROOT="$BATS_FILE_TMPDIR"
}

# the last 16 characters of a key's fingerprint, as check_keys.sh prints it.
short_fingerprint() {
  local name="$1"

  GNUPGHOME="$(home_of "$name")" fingerprint_of "$name" | cut -c 25-
}

# the tests share a keyring, so each one sets whether "missing" is imported.
import_missing_key() {
  GNUPGHOME="$MISSING_GNUPGHOME" gpg --export missing@test | gpg_quiet --import
}

remove_missing_key() {
  local fingerprint
  fingerprint=$(GNUPGHOME="$MISSING_GNUPGHOME" fingerprint_of missing)
  gpg_quiet --delete-keys "$fingerprint" || true
}

# writes a package script listing the given "<name>=<file in the key folder>"
# keys.
write_package() {
  mkdir -p "$repo_dir/packages/test"
  {
    echo 'key_fingerprints=('

    local key
    for key in "$@"; do
      local name="${key%%=*}"
      local fingerprint
      fingerprint=$(GNUPGHOME="$(home_of "$name")" fingerprint_of "$name")
      echo "  '$fingerprint' # $KEYS_URL/${key#*=}"
    done

    echo ')'
  } > "$repo_dir/packages/test/verify.sh"
}

# these keys are at the repo's root, which isn't a key folder, so they're not
# compared with a folder listing.
write_root_package() {
  mkdir -p "$repo_dir/packages/test"
  {
    echo 'key_fingerprints=('

    local name
    for name in "$@"; do
      echo "  '$(fingerprint_of "$name")' # $REPO_URL/$name.asc"
    done

    echo ')'
  } > "$repo_dir/packages/test/verify.sh"
}

# writes a package script listing one of signer's keys at the given url.
write_signer_package() {
  local url="$1"

  mkdir -p "$repo_dir/packages/test"
  printf "key_fingerprints=(\n  '%s' # %s\n)\n" "$(fingerprint_of signer)" \
    "$url" > "$repo_dir/packages/test/verify.sh"
}

@test 'passes when every key in the folder is listed, imported, and usable' {
  write_package "${ALL_KEYS[@]}"
  import_missing_key

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'--- 0 problems, 1 warnings'* ]]
}

@test 'warns about an expired key without failing' {
  write_package "${ALL_KEYS[@]}"
  import_missing_key

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 0 ]
  local id
  id=$(short_fingerprint expired)
  [[ "$output" == *"warning: expired.asc ($id) expired on 2020-12-31"* ]]
}

@test 'reports a listed key that is not imported' {
  write_package "${ALL_KEYS[@]}"
  remove_missing_key

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 1 ]
  local id
  id=$(short_fingerprint missing)
  [[ "$output" == *"problem: missing.asc ($id) isn't imported"* ]]
}

@test 'imports only the listed key from a file with others' {
  write_package missing=missing.asc
  GNUPGHOME=$(mktemp -d /tmp/verify-from-gpg-test.XXXXXX)

  run "$repo_dir/check_keys.sh" --import

  local missing_fingerprint unwanted_fingerprint
  missing_fingerprint=$(GNUPGHOME="$MISSING_GNUPGHOME" fingerprint_of missing)
  unwanted_fingerprint=$(GNUPGHOME="$MISSING_GNUPGHOME" fingerprint_of unwanted)
  gpg --list-keys "$missing_fingerprint"

  run gpg --list-keys "$unwanted_fingerprint"
  [ "$status" -ne 0 ]

  gpgconf --kill gpg-agent
  rm -rf "${GNUPGHOME:?}"
}

@test 'reports a key that can no longer be downloaded' {
  write_package signer=deleted.asc

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 1 ]
  local id
  id=$(short_fingerprint signer)
  [[ "$output" == *"problem: deleted.asc ($id) can no longer be downloaded"* ]]
}

@test 'reports a key that is no longer in its file' {
  write_package signer=stranger.asc

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 1 ]
  local id
  id=$(short_fingerprint signer)
  [[ "$output" == *"problem: stranger.asc ($id) is no longer in"* ]]
}

@test 'reports unlisted keys in the folder, but not listed keys renamed' {
  write_package signer=signer.asc

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 1 ]
  local problem='problem: owner/keys has keys'
  [[ "$output" == *"$problem/expired.asc, which isn't listed"* ]]
  [[ "$output" == *"$problem/stranger.asc, which isn't listed"* ]]
  [[ "$output" == *"$problem/missing.asc, which isn't listed"* ]]
  [[ "$output" != *'signer-alias.asc'* ]]
  [[ "$output" != *'README.md'* ]]
}

@test 'reports a revoked key' {
  write_root_package revoked

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 1 ]
  local id
  id=$(short_fingerprint revoked)
  [[ "$output" == *"problem: revoked.asc ($id) is revoked"* ]]
}

@test 'warns about a key whose signing subkeys have all expired' {
  write_root_package no-signing-key

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 0 ]
  local id
  id=$(short_fingerprint no-signing-key)
  local warning="warning: no-signing-key.asc ($id) has no usable signing key"
  [[ "$output" == *"$warning"* ]]
}

@test 'does not compare keys at a repo root with a folder listing' {
  write_root_package signer

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'--- 0 problems, 0 warnings'* ]]
}

@test 'names a keyserver lookup by its host' {
  local fingerprint
  fingerprint=$(fingerprint_of signer)
  write_signer_package \
    "https://keyserver.example/pks/lookup?op=get&search=0x$fingerprint"

  # an empty keyring, so the key is reported as not imported.
  local empty_gnupghome
  empty_gnupghome=$(mktemp -d /tmp/verify-from-gpg-test.XXXXXX)

  GNUPGHOME="$empty_gnupghome" run "$repo_dir/check_keys.sh"

  GNUPGHOME="$empty_gnupghome" gpgconf --kill gpg-agent
  rm -rf "${empty_gnupghome:?}"

  [ "$status" -eq 1 ]
  local id="${fingerprint: -16}"
  [[ "$output" == *"problem: keyserver.example ($id) isn't imported"* ]]
}

@test 'reports a key folder that cannot be listed' {
  local unlisted_path='raw.githubusercontent.com/owner/unlisted-repo/main/keys'
  write_signer_package "https://$unlisted_path/signer.asc"
  mkdir -p "$FAKE_CURL_ROOT/$unlisted_path"
  cp "$FAKE_CURL_ROOT/$REPO_PATH/keys/signer.asc" \
    "$FAKE_CURL_ROOT/$unlisted_path/"

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 1 ]
  local problem='problem: couldn'\''t list owner/unlisted-repo/keys'
  [[ "$output" == *"$problem to check for unlisted keys"* ]]
}
