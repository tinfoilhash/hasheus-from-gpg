#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
  create_repo
  # shellcheck source=../common/common.sh
  source "$repo_dir/common/common.sh"
  state_file="$XDG_CONFIG_HOME/verify-from-gpg/test"
}

@test 'checks the last 3 releases when there is no state' {
  source_state test

  [ "$last_release_published_at" = '1970-01-01T00:00:00Z' ]
  [ "$limit" -eq 3 ]
}

@test 'checks up to 30 releases since the saved release date' {
  set_state test '2026-09-17T10:08:33Z'

  source_state test

  [ "$last_release_published_at" = '2026-09-17T10:08:33Z' ]
  [ "$limit" -eq 30 ]
}

@test 'reads every release date format in use' {
  local published_at
  for published_at in '2026-09-17T10:08:33Z' '2026-07-13T00:00:00+0000' '2026-07-31T1608'; do
    set_state test "$published_at"
    source_state test
    [ "$last_release_published_at" = "$published_at" ]
  done
}

@test 'rejects state that would run code without running it' {
  mkdir -p "${state_file%/*}"
  echo "last_release_published_at='x';touch $BATS_TEST_TMPDIR/ran;'" > "$state_file"

  run source_state test

  [ "$status" -eq 1 ]
  [ "$output" = "invalid state in $state_file, exiting" ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test 'rejects state with extra lines' {
  mkdir -p "${state_file%/*}"
  printf "last_release_published_at='2026-01-01T00:00:00Z'\nextra\n" > "$state_file"

  run source_state test

  [ "$status" -eq 1 ]
}

@test 'records the release and removes its directory' {
  mkdir -p "${state_file%/*}"
  package_dir="$BATS_TEST_TMPDIR"
  start_release

  complete_release test '2026-10-01T16:46:15Z'

  [ "$(state_of test)" = '2026-10-01T16:46:15Z' ]
  [ ! -e "$release_dir" ]
}

@test 'refuses to record a release date with non-timestamp characters' {
  set_state test '2026-07-31T1608'
  package_dir="$BATS_TEST_TMPDIR"
  start_release

  run complete_release test "2026-01-01';touch $BATS_TEST_TMPDIR/ran;'"

  [ "$status" -eq 1 ]
  [ "$(state_of test)" = '2026-07-31T1608' ]
}
