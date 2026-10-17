#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup_file() {
  setup_keyring

  cd "$BATS_FILE_TMPDIR" || exit 1
  echo 'hashes' > data.txt
  echo 'tampered hashes' > tampered.txt

  sign_detached signer data.txt signer.sig
  sign_detached stranger data.txt stranger.sig
  sign_detached 'signer missing' data.txt signer-and-missing.sig
  sign_clear signer data.txt signer.asc
  sign_clear stranger data.txt stranger.asc

  # one good signature from a listed key plus one bad signature.
  sign_detached stranger tampered.txt stranger-over-tampered.sig
  cat signer.sig stranger-over-tampered.sig > signer-and-bad.sig

  # a revoked key, using the revocation certificate gpg saves when it makes a
  # key.
  gpg_quiet --quick-gen-key revoked@test ed25519 sign never
  sign_detached revoked data.txt revoked.sig
  sed 's/^:-----/-----/' \
    "$GNUPGHOME/openpgp-revocs.d/$(fingerprint_of revoked).rev" \
    | gpg_quiet --import

  # a key that expired at the end of 2020, with signatures made before and after
  # that. gpg won't sign with an expired key, so sign first and then set the
  # expiry.
  gpg_quiet --faked-system-time 20200101T000000! \
    --quick-gen-key expired@test ed25519 sign never
  gpg_quiet --faked-system-time 20200601T000000! \
    -u expired@test --detach-sign -o before-expiry.sig data.txt
  gpg_quiet --faked-system-time 20220101T000000! \
    -u expired@test --detach-sign -o after-expiry.sig data.txt
  gpg_quiet --faked-system-time 20200102T000000! \
    --quick-set-expire "$(fingerprint_of expired)" 20201231T000000
  cat signer.sig after-expiry.sig > signer-and-after-expiry.sig
}

teardown_file() {
  teardown_keyring
}

setup() {
  # shellcheck source=../common/common.sh
  source "$PROJECT_DIR/common/common.sh"
  cd "$BATS_FILE_TMPDIR" || exit 1

  signer=$(fingerprint_of signer)
  other=$(fingerprint_of other)
  stranger=$(fingerprint_of stranger)
  revoked=$(fingerprint_of revoked)
  expired=$(fingerprint_of expired)
}

@test 'passes for a signature from a listed key' {
  run verify_gpg_signature signer.sig data.txt "$other" "$signer"
  [ "$status" -eq 0 ]
}

@test 'fails when the signer is not listed' {
  run verify_gpg_signature signer.sig data.txt "$other"
  [ "$status" -eq 1 ]
}

@test 'fails for a signature from a key in the keyring that is not listed' {
  run verify_gpg_signature stranger.sig data.txt "$signer"
  [ "$status" -eq 1 ]
}

@test "passes when another signer's key is missing" {
  run verify_gpg_signature signer-and-missing.sig data.txt "$signer"
  [ "$status" -eq 0 ]
}

@test 'fails when the signed data was changed' {
  run verify_gpg_signature signer.sig tampered.txt "$signer"
  [ "$status" -eq 1 ]
}

@test 'passes for a good signature from a listed key alongside a bad one' {
  run verify_gpg_signature signer-and-bad.sig data.txt "$signer"
  [ "$status" -eq 0 ]
}

@test 'fails when the only signature from a listed key is bad' {
  run verify_gpg_signature signer-and-bad.sig data.txt "$stranger"
  [ "$status" -eq 1 ]
}

@test 'passes for a clearsigned file from a listed key' {
  run verify_gpg_signature signer.asc '' "$signer"
  [ "$status" -eq 0 ]
}

@test 'fails for a clearsigned file from a key that is not listed' {
  run verify_gpg_signature stranger.asc '' "$signer"
  [ "$status" -eq 1 ]
}

@test 'matches fingerprints regardless of case' {
  run verify_gpg_signature signer.sig data.txt "$(tr 'A-F' 'a-f' <<< "$signer")"
  [ "$status" -eq 0 ]
}

@test 'matches a listed signing subkey fingerprint' {
  run verify_gpg_signature signer.sig data.txt "$(signing_subkey_of signer)"
  [ "$status" -eq 0 ]
}

@test 'fails for a listed subkey that did not make the signature' {
  run verify_gpg_signature stranger.sig data.txt "$(signing_subkey_of signer)"
  [ "$status" -eq 1 ]
}

@test 'fails for a signature from a revoked key' {
  run verify_gpg_signature revoked.sig data.txt "$revoked"
  [ "$status" -eq 1 ]
}

@test 'passes for a signature made before the key expired' {
  run verify_gpg_signature before-expiry.sig data.txt "$expired"
  [ "$status" -eq 0 ]
}

@test 'fails for a signature made after the key expired' {
  run verify_gpg_signature after-expiry.sig data.txt "$expired"
  [ "$status" -eq 1 ]
}

@test "passes for a listed key's signature alongside one made after expiry" {
  run verify_gpg_signature signer-and-after-expiry.sig data.txt \
    "$expired" "$signer"
  [ "$status" -eq 0 ]
}
