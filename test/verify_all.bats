#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
  repo_dir="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo_dir"
  cp "$PROJECT_DIR/verify_all.sh" "$repo_dir/"
}

# writes a package script that reads all of stdin, like a command that would
# consume the list of scripts.
write_package() {
  local package_name="$1"
  local exit_status="$2"

  mkdir -p "$repo_dir/packages/$package_name"
  cat > "$repo_dir/packages/$package_name/verify.sh" << EOF
#!/usr/bin/env bash
cat > /dev/null
echo "ran $package_name"
exit $exit_status
EOF
  chmod +x "$repo_dir/packages/$package_name/verify.sh"
}

@test 'runs every package in order, even when a package reads stdin' {
  write_package c 0
  write_package a 0
  write_package b 0

  run "$repo_dir/verify_all.sh"

  [ "$status" -eq 0 ]
  [ "$(grep '^ran' <<< "$output" | tr '\n' ' ')" = 'ran a ran b ran c ' ]
}

@test 'exits 1 when any package fails, after running the rest' {
  write_package a 0
  write_package b 1
  write_package c 0

  run "$repo_dir/verify_all.sh"

  [ "$status" -eq 1 ]
  [ "$(grep -c '^ran' <<< "$output")" -eq 3 ]
}

@test 'works from any directory' {
  write_package a 0
  cd / || exit 1

  run "$repo_dir/verify_all.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'ran a'* ]]
}

@test 'exits 1 when no packages are found' {
  mkdir -p "$repo_dir/packages"

  run "$repo_dir/verify_all.sh"

  [ "$status" -eq 1 ]
  [ "$output" = 'no packages found, exiting' ]
}

@test 'writes each package log and status to LOG_DIR' {
  write_package a 0
  write_package b 1

  LOG_DIR="$BATS_TEST_TMPDIR/logs" run "$repo_dir/verify_all.sh"

  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$(cat "$BATS_TEST_TMPDIR/logs/a.log")" = 'ran a' ]
  [ "$(cat "$BATS_TEST_TMPDIR/logs/b.log")" = 'ran b' ]
  [ "$(tr '\n' ' ' < "$BATS_TEST_TMPDIR/logs/status.txt")" = 'a 0 b 1 ' ]
}
