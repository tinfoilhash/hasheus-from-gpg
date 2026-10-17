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

  # One good signature from a listed key plus one bad signature.
  sign_detached stranger tampered.txt stranger-over-tampered.sig
  cat signer.sig stranger-over-tampered.sig > signer-and-bad.sig
}

teardown_file() {
  teardown_keyring
}

setup() {
  # shellcheck source=../common/common.sh
  source "$PROJECT_DIR/common/common.sh"
  cd "$BATS_FILE_TMPDIR" || exit 1
}

@test 'passes for a signature from a listed key' {
  run verify_gpg_signature signer.sig data.txt "$(fingerprint_of other)" "$(fingerprint_of signer)"
  [ "$status" -eq 0 ]
}

@test 'fails when the signer is not listed' {
  run verify_gpg_signature signer.sig data.txt "$(fingerprint_of other)"
  [ "$status" -eq 1 ]
}

@test 'fails for a signature from a key in the keyring that is not listed' {
  run verify_gpg_signature stranger.sig data.txt "$(fingerprint_of signer)"
  [ "$status" -eq 1 ]
}

@test "passes when another signer's key is missing" {
  run verify_gpg_signature signer-and-missing.sig data.txt "$(fingerprint_of signer)"
  [ "$status" -eq 0 ]
}

@test 'fails when the signed data was changed' {
  run verify_gpg_signature signer.sig tampered.txt "$(fingerprint_of signer)"
  [ "$status" -eq 1 ]
}

@test 'fails when any signature is bad, even with a good one from a listed key' {
  run verify_gpg_signature signer-and-bad.sig data.txt "$(fingerprint_of signer)"
  [ "$status" -eq 1 ]
}

@test 'passes for a clearsigned file from a listed key' {
  run verify_gpg_signature signer.asc '' "$(fingerprint_of signer)"
  [ "$status" -eq 0 ]
}

@test 'fails for a clearsigned file from a key that is not listed' {
  run verify_gpg_signature stranger.asc '' "$(fingerprint_of signer)"
  [ "$status" -eq 1 ]
}

@test 'matches fingerprints regardless of case' {
  run verify_gpg_signature signer.sig data.txt "$(fingerprint_of signer | tr 'A-F' 'a-f')"
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
