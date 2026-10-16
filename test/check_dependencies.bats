#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

PUBKEY_HEX='46fc4feba53427642bf90f3a9addad6288c77f93a756692c9988794fbd97a5b3'

setup() {
  create_repo
  # shellcheck source=../common/common.sh
  source "$repo_dir/common/common.sh"
  unset NSEC PUBKEY DRY_RUN
}

@test 'exits when NSEC is not set' {
  run check_dependencies

  [ "$status" -eq 1 ]
  [ "$output" = '$NSEC not set, exiting' ]
}

@test 'derives the public key from NSEC' {
  NSEC='nsec-fake' check_dependencies

  [[ "$npub_hex" =~ ^[0-9a-f]{64}$ ]]
}

@test 'accepts PUBKEY instead of NSEC in a dry run' {
  DRY_RUN=1 PUBKEY="$PUBKEY_HEX" check_dependencies

  [ "$npub_hex" = "$PUBKEY_HEX" ]
}

@test 'requires NSEC outside a dry run, even with PUBKEY' {
  PUBKEY="$PUBKEY_HEX" run check_dependencies

  [ "$status" -eq 1 ]
  [ "$output" = '$NSEC not set, exiting' ]
}

@test 'rejects an invalid PUBKEY' {
  DRY_RUN=1 PUBKEY='npub1notahexkey' run check_dependencies

  [ "$status" -eq 1 ]
  [[ "$output" == *'$PUBKEY is invalid, exiting' ]]
}
