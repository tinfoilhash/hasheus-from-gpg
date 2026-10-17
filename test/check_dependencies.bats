#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

TEST_NPUB='npub1gm7yl6a9xsnkg2lepuaf4hddv2yvwlun5atxjtye3pu5l0vh5kes8ef4r5'

setup() {
  create_repo
  # shellcheck source=../common/common.sh
  source "$repo_dir/common/common.sh"
  unset NSEC NPUB DRY_RUN
}

@test 'exits when a dependency is missing' {
  local bin_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin_dir"

  local command
  for command in curl file gh gpg hq jaq nak shasum; do
    ln -s "$(command -v "$command")" "$bin_dir/$command"
  done

  PATH="$bin_dir" NSEC='nsec-fake' run check_dependencies

  [ "$status" -eq 1 ]
  [ "$output" = 'xmllint not found, exiting' ]
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

@test 'accepts NPUB instead of NSEC in a dry run' {
  DRY_RUN=1 NPUB="$TEST_NPUB" check_dependencies

  [ "$npub_hex" = "$(printf '%064d' 1)" ]
}

@test 'requires NSEC outside a dry run, even with NPUB' {
  NPUB="$TEST_NPUB" run check_dependencies

  [ "$status" -eq 1 ]
  [ "$output" = '$NSEC not set, exiting' ]
}

@test 'rejects an invalid NPUB' {
  DRY_RUN=1 NPUB='npub1notvalid' run check_dependencies

  [ "$status" -eq 1 ]
  [[ "$output" == *'$NPUB is invalid, exiting' ]]
}

@test 'treats any DRY_RUN value but 0 as a dry run' {
  local value
  for value in 1 true yes; do
    DRY_RUN="$value" run is_dry_run
    [ "$status" -eq 0 ]
  done

  DRY_RUN=0 run is_dry_run
  [ "$status" -eq 1 ]

  DRY_RUN='' run is_dry_run
  [ "$status" -eq 1 ]
}
