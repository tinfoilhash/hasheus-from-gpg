#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

KEYS_URL='https://raw.githubusercontent.com/owner/keys/main/keys'

setup_file() {
  setup_keyring

  # An expired key, made by pretending it's 2020.
  gpg_quiet --faked-system-time 20200101T000000! --quick-gen-key expired@test ed25519 sign 1y

  # A revoked key, using the revocation certificate gpg saves when it makes a key.
  gpg_quiet --quick-gen-key revoked@test ed25519 sign never
  sed 's/^:-----/-----/' "$GNUPGHOME/openpgp-revocs.d/$(fingerprint_of revoked).rev" | gpg_quiet --import

  # A key whose only signing subkey expired, made by pretending it's 2020.
  gpg_quiet --faked-system-time 20200101T000000! --quick-gen-key no-signing-key@test ed25519 cert never
  gpg_quiet --faked-system-time 20200101T000000! --quick-add-key "$(fingerprint_of no-signing-key)" ed25519 sign 1y

  # A key that's only in the missing keyring, to be offered alongside "missing" in one file.
  GNUPGHOME="$MISSING_GNUPGHOME" gpg_quiet --quick-gen-key unwanted@test ed25519 sign never

  local keys_dir="$BATS_FILE_TMPDIR/site/raw.githubusercontent.com/owner/keys/main/keys"
  mkdir -p "$keys_dir"

  gpg --armor --export signer@test > "$keys_dir/signer.asc"
  gpg --armor --export signer@test > "$keys_dir/signer-alias.asc"
  gpg --armor --export expired@test > "$keys_dir/expired.asc"
  gpg --armor --export signer@test > "$BATS_FILE_TMPDIR/site/raw.githubusercontent.com/owner/keys/main/signer.asc"
  gpg --armor --export revoked@test > "$BATS_FILE_TMPDIR/site/raw.githubusercontent.com/owner/keys/main/revoked.asc"
  gpg --armor --export no-signing-key@test > "$BATS_FILE_TMPDIR/site/raw.githubusercontent.com/owner/keys/main/no-signing-key.asc"

  # A keyserver lookup, which has no file name.
  mkdir -p "$BATS_FILE_TMPDIR/site/keyserver.example/pks"
  gpg --armor --export signer@test > "$BATS_FILE_TMPDIR/site/keyserver.example/pks/lookup?op=get&search=0x$(fingerprint_of signer)"
  gpg --armor --export stranger@test > "$keys_dir/stranger.asc"
  GNUPGHOME="$MISSING_GNUPGHOME" gpg --armor --export missing@test unwanted@test > "$keys_dir/missing.asc"

  # The key folder's listing, as GitHub's contents API returns it.
  mkdir -p "$BATS_FILE_TMPDIR/api/repos/owner/keys/contents"
  local path
  for path in "$keys_dir"/*.asc; do
    jaq -n --arg name "${path##*/}" --arg url "$KEYS_URL/${path##*/}" \
      '{ type: "file", name: $name, download_url: $url }'
  done | jaq -s '. + [{ type: "file", name: "README.md", download_url: "" }]' \
    > "$BATS_FILE_TMPDIR/api/repos/owner/keys/contents/keys.json"
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

# The tests share a keyring, so each one sets whether "missing" is imported.
import_missing_key() {
  GNUPGHOME="$MISSING_GNUPGHOME" gpg --export missing@test | gpg_quiet --import
}

remove_missing_key() {
  gpg_quiet --delete-keys "$(GNUPGHOME="$MISSING_GNUPGHOME" fingerprint_of missing)" || true
}

# Writes a package script listing the given "<name>=<file in the key folder>" keys.
write_package() {
  mkdir -p "$repo_dir/packages/test"
  {
    echo 'key_fingerprints=('

    local key
    for key in "$@"; do
      local fingerprint
      fingerprint=$(GNUPGHOME="$(home_of "${key%%=*}")" fingerprint_of "${key%%=*}")
      echo "  '$fingerprint' # $KEYS_URL/${key#*=}"
    done

    echo ')'
  } > "$repo_dir/packages/test/verify.sh"
}

@test 'passes when every key in the folder is listed, imported, and usable' {
  write_package signer=signer.asc expired=expired.asc stranger=stranger.asc missing=missing.asc
  import_missing_key

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'--- 0 problems, 1 warnings'* ]]
}

@test 'warns about an expired key without failing' {
  write_package signer=signer.asc expired=expired.asc stranger=stranger.asc missing=missing.asc
  import_missing_key

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: expired.asc ($(fingerprint_of expired | cut -c 25-)) expired on 2020-12-31"* ]]
}

@test 'reports a listed key that is not imported' {
  write_package signer=signer.asc expired=expired.asc stranger=stranger.asc missing=missing.asc
  remove_missing_key

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"problem: missing.asc ($(GNUPGHOME="$MISSING_GNUPGHOME" fingerprint_of missing | cut -c 25-)) isn't imported"* ]]
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
  [[ "$output" == *"problem: deleted.asc ($(fingerprint_of signer | cut -c 25-)) can no longer be downloaded"* ]]
}

@test 'reports a key that is no longer in its file' {
  write_package signer=stranger.asc

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"problem: stranger.asc ($(fingerprint_of signer | cut -c 25-)) is no longer in"* ]]
}

@test 'reports keys in the folder that are not listed, but not the same key under another name' {
  write_package signer=signer.asc

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'problem: owner/keys has keys/expired.asc, which isn'\''t listed'* ]]
  [[ "$output" == *'problem: owner/keys has keys/stranger.asc, which isn'\''t listed'* ]]
  [[ "$output" == *'problem: owner/keys has keys/missing.asc, which isn'\''t listed'* ]]
  [[ "$output" != *'signer-alias.asc'* ]]
  [[ "$output" != *'README.md'* ]]
}

# These keys are at the repo's root, which isn't a key folder, so they're not compared with a folder listing.
write_root_package() {
  mkdir -p "$repo_dir/packages/test"
  {
    echo 'key_fingerprints=('

    local name
    for name in "$@"; do
      echo "  '$(fingerprint_of "$name")' # https://raw.githubusercontent.com/owner/keys/main/$name.asc"
    done

    echo ')'
  } > "$repo_dir/packages/test/verify.sh"
}

@test 'reports a revoked key' {
  write_root_package revoked

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"problem: revoked.asc ($(fingerprint_of revoked | cut -c 25-)) is revoked"* ]]
}

@test 'warns about a key whose signing subkeys have all expired' {
  write_root_package no-signing-key

  run "$repo_dir/check_keys.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: no-signing-key.asc ($(fingerprint_of no-signing-key | cut -c 25-)) has no usable signing key"* ]]
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
  mkdir -p "$repo_dir/packages/test"
  printf "key_fingerprints=(\n  '%s' # https://keyserver.example/pks/lookup?op=get&search=0x%s\n)\n" "$fingerprint" "$fingerprint" \
    > "$repo_dir/packages/test/verify.sh"

  # An empty keyring, so the key is reported as not imported.
  GNUPGHOME=$(mktemp -d /tmp/verify-from-gpg-test.XXXXXX) run "$repo_dir/check_keys.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"problem: keyserver.example (${fingerprint: -16}) isn't imported"* ]]
}
