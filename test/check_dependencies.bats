#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
  create_repo
  # shellcheck source=../common/common.sh
  source "$repo_dir/common/common.sh"
  unset HASHEUS_PUBLIC_KEY HASHEUS_SECRET_KEY DRY_RUN
}

@test 'exits when a dependency is missing' {
  local bin_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin_dir"

  local command
  for command in curl file gh gpg hasheus hq jaq shasum unzip; do
    ln -s "$(command -v "$command")" "$bin_dir/$command"
  done

  PATH="$bin_dir" run check_dependencies

  [ "$status" -eq 1 ]
  [ "$output" = 'xmllint not found, exiting' ]
}

@test 'exits when HASHEUS_PUBLIC_KEY is not set, even with the secret key' {
  HASHEUS_SECRET_KEY='nsec1fake' run check_dependencies

  [ "$status" -eq 1 ]
  [ "$output" = '$HASHEUS_PUBLIC_KEY not set, exiting' ]
}

@test 'exits when HASHEUS_SECRET_KEY is not set outside a dry run' {
  HASHEUS_PUBLIC_KEY='npub1fake' run check_dependencies

  [ "$status" -eq 1 ]
  [ "$output" = '$HASHEUS_SECRET_KEY not set, exiting' ]
}

@test 'accepts both keys' {
  HASHEUS_PUBLIC_KEY='npub1fake' HASHEUS_SECRET_KEY='nsec1fake' \
    run check_dependencies

  [ "$status" -eq 0 ]
}

@test 'accepts only HASHEUS_PUBLIC_KEY in a dry run' {
  DRY_RUN=1 HASHEUS_PUBLIC_KEY='npub1fake' run check_dependencies

  [ "$status" -eq 0 ]
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
