#!/usr/bin/env bats

# runs scheduled_run/install.sh from a scratch checkout whose origin is a local
# repo, with HOME in a temp directory and the fake systemctl and loginctl.

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

unit='hasheus-from-gpg-scheduled-run'

git_quiet() {
  git -c user.name=test -c user.email=test@test -c init.defaultBranch=main \
    -c commit.gpgsign=false \
    "$@" -q
}

setup() {
  local work_dir="$BATS_TEST_TMPDIR/work"
  mkdir -p "$work_dir/scheduled_run"
  cp "$PROJECT_DIR/scheduled_run/install.sh" "$work_dir/scheduled_run/"
  git_quiet -C "$work_dir" init
  git -C "$work_dir" add .
  git_quiet -C "$work_dir" commit -m 'scratch repo'

  origin_dir="$BATS_TEST_TMPDIR/origin.git"
  checkout_dir="$BATS_TEST_TMPDIR/checkout"
  git_quiet clone --bare "$work_dir" "$origin_dir"
  git_quiet clone "$origin_dir" "$checkout_dir"

  export HOME="$BATS_TEST_TMPDIR/home"
  export SHELL=/bin/bash
  export PATH="$PROJECT_DIR/test/fakes:$PATH"
  export FAKE_SYSTEMCTL_LOG="$BATS_TEST_TMPDIR/systemctl.log"
  export FAKE_LINGER=1
  unset SCHEDULED_RUN_CLONE_DIR SCHEDULED_RUN_LOG_DIR SCHEDULED_RUN_HOURS \
    SCHEDULED_RUN_WEEKDAYS HASHEUS_PUBLIC_KEY HASHEUS_SECRET_KEY \
    XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
  mkdir -p "$HOME"
  printf '%s\n' 'export HASHEUS_PUBLIC_KEY=npub1fake' \
    'export HASHEUS_SECRET_KEY=nsec1fake' > "$HOME/.bash_profile"

  clone_dir="$HOME/.local/share/hasheus-from-gpg/repo"
  log_dir="$HOME/.local/state/hasheus-from-gpg/logs"
  service="$HOME/.config/systemd/user/$unit.service"
  timer="$HOME/.config/systemd/user/$unit.timer"
}

run_install() {
  run "$checkout_dir/scheduled_run/install.sh" "$@"
}

@test 'clones origin into a scheduled run clone' {
  run_install

  [ "$status" -eq 0 ]
  [ "$(git -C "$clone_dir" config hasheus-from-gpg.scheduledRun)" = true ]
  local helpers
  helpers=$(git -C "$clone_dir" config --local --get-all credential.helper)
  [ "$(tr '\n' ' ' <<< "$helpers")" = ' !gh auth git-credential ' ]
  [ "$(git -C "$clone_dir" rev-parse HEAD)" = \
    "$(git -C "$origin_dir" rev-parse main)" ]
}

@test 'writes the service with the shell and paths filled in' {
  run_install

  [ "$status" -eq 0 ]
  grep -qxF \
    "ExecStart=\"/bin/bash\" -l -c \"'$clone_dir/scheduled_run/run.sh'\"" \
    "$service"
  grep -qxF "Environment=\"SCHEDULED_RUN_LOG_DIR=$log_dir\"" "$service"
  grep -qx 'Persistent=true' "$timer"
  [ -d "$log_dir" ]
}

@test 'writes units systemd accepts' {
  command -v systemd-analyze > /dev/null || skip 'no systemd-analyze'

  SCHEDULED_RUN_CLONE_DIR="$BATS_TEST_TMPDIR/my clone" \
    SCHEDULED_RUN_HOURS=9,18 SCHEDULED_RUN_WEEKDAYS=0,6 run_install

  [ "$status" -eq 0 ]
  # verify checks that ExecStart's program exists, which it does, and parses
  # the rest of both units.
  run systemd-analyze --user verify "$service" "$timer"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  systemd-analyze calendar "$(calendar_of)" > /dev/null
}

@test 'uses SCHEDULED_RUN_CLONE_DIR and SCHEDULED_RUN_LOG_DIR' {
  SCHEDULED_RUN_CLONE_DIR="$BATS_TEST_TMPDIR/my clone" \
    SCHEDULED_RUN_LOG_DIR="$BATS_TEST_TMPDIR/my logs" run_install

  [ "$status" -eq 0 ]
  local is_marked
  is_marked=$(git -C "$BATS_TEST_TMPDIR/my clone" config \
    hasheus-from-gpg.scheduledRun)
  [ "$is_marked" = true ]
  grep -qF "'$BATS_TEST_TMPDIR/my clone/scheduled_run/run.sh'" "$service"
  grep -qF "SCHEDULED_RUN_LOG_DIR=$BATS_TEST_TMPDIR/my logs\"" "$service"
  [ -d "$BATS_TEST_TMPDIR/my logs" ]
}

@test 'uses the XDG folders when they are set' {
  XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config" \
    XDG_DATA_HOME="$BATS_TEST_TMPDIR/data" \
    XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" run_install

  [ "$status" -eq 0 ]
  local xdg_service="$BATS_TEST_TMPDIR/config/systemd/user/$unit.service"
  grep -qF "'$BATS_TEST_TMPDIR/data/hasheus-from-gpg/repo/" "$xdg_service"
  grep -qF "=$BATS_TEST_TMPDIR/state/hasheus-from-gpg/logs\"" "$xdg_service"
}

# prints the timer's OnCalendar value.
calendar_of() {
  sed -n 's/^OnCalendar=//p' "$timer"
}

@test 'schedules 9:00 every day by default' {
  run_install

  [ "$status" -eq 0 ]
  [ "$(calendar_of)" = '*-*-* 9:00:00' ]
  [[ "$output" == *'at 9:00 every day'* ]]
}

@test 'schedules each of SCHEDULED_RUN_HOURS, like every 4 hours' {
  SCHEDULED_RUN_HOURS=1,5,9,13,17,21 run_install

  [ "$status" -eq 0 ]
  [ "$(calendar_of)" = '*-*-* 1,5,9,13,17,21:00:00' ]
}

@test 'schedules only SCHEDULED_RUN_WEEKDAYS, like once a week' {
  SCHEDULED_RUN_HOURS=9,18 SCHEDULED_RUN_WEEKDAYS=1,5 run_install

  [ "$status" -eq 0 ]
  [ "$(calendar_of)" = 'Mon,Fri *-*-* 9,18:00:00' ]
  [[ "$output" == *'at 9:00, 18:00 on weekdays 1,5'* ]]
}

@test 'refuses hours or weekdays out of range' {
  SCHEDULED_RUN_HOURS=24 run_install
  [ "$status" -eq 1 ]
  [[ "$output" == *'SCHEDULED_RUN_HOURS must be hours from 0 to 23'* ]]

  SCHEDULED_RUN_WEEKDAYS=7 run_install
  [ "$status" -eq 1 ]
  [[ "$output" == *'SCHEDULED_RUN_WEEKDAYS must be days from 0'* ]]
  [ ! -f "$timer" ]
}

@test 'refuses paths that would break the units or the job' {
  local dir
  for dir in "$BATS_TEST_TMPDIR/it's" "$BATS_TEST_TMPDIR/a\"b" \
    "$BATS_TEST_TMPDIR/a\\b" "$BATS_TEST_TMPDIR/\$HOME" \
    "$BATS_TEST_TMPDIR/%h" 'relative/clone'; do
    SCHEDULED_RUN_CLONE_DIR="$dir" run_install

    [ "$status" -eq 1 ]
    [[ "$output" == *'SCHEDULED_RUN_CLONE_DIR must be an absolute path'* ]]
  done

  [ ! -f "$timer" ]
}

@test 'exits when systemd does not load the timer' {
  FAKE_SYSTEMCTL_RELOAD_FAILS=1 run_install

  [ "$status" -eq 1 ]
  [[ "$output" != *'installed'* ]]
}

@test 'warns about keys set only in the shell running the install' {
  rm "$HOME/.bash_profile"

  HASHEUS_PUBLIC_KEY=npub1fake HASHEUS_SECRET_KEY=nsec1fake run_install

  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: HASHEUS_PUBLIC_KEY isn't set"* ]]
  [[ "$output" == *"warning: HASHEUS_SECRET_KEY isn't set"* ]]
}

@test 'enables the timer, restarting it on a reinstall' {
  run_install
  run_install

  [ "$status" -eq 0 ]
  [[ "$output" == *'using the existing clone'* ]]
  [ "$(grep -cx -- '--user daemon-reload' "$FAKE_SYSTEMCTL_LOG")" -eq 2 ]
  [ "$(grep -cx -- "--user enable -q $unit.timer" "$FAKE_SYSTEMCTL_LOG")" \
    -eq 2 ]
  [ "$(grep -cx -- "--user restart $unit.timer" "$FAKE_SYSTEMCTL_LOG")" -eq 2 ]
}

@test 'warns when lingering is off' {
  FAKE_LINGER='' run_install

  [ "$status" -eq 0 ]
  [[ "$output" == *'warning: lingering is off'* ]]
}

@test 'refuses to use a folder that is not a scheduled run clone' {
  mkdir -p "$clone_dir"

  run_install

  [ "$status" -eq 1 ]
  [[ "$output" == *"exists but isn't a scheduled run clone"* ]]
  [ ! -f "$timer" ]
}

@test 'warns when the login shell does not set a key' {
  echo 'export HASHEUS_PUBLIC_KEY=npub1fake' > "$HOME/.bash_profile"

  run_install

  [ "$status" -eq 0 ]
  [[ "$output" != *"warning: HASHEUS_PUBLIC_KEY isn't set"* ]]
  [[ "$output" == *"warning: HASHEUS_SECRET_KEY isn't set"* ]]
}

@test 'does not warn when the login shell sets both keys' {
  run_install

  [ "$status" -eq 0 ]
  [[ "$output" != *'warning'* ]]
}

@test 'uninstalls the job and the clone, keeping the logs' {
  run_install
  touch "$log_dir/kept.log"

  run_install --uninstall

  [ "$status" -eq 0 ]
  grep -qx -- "--user disable -q --now $unit.timer" "$FAKE_SYSTEMCTL_LOG"
  grep -qx -- "--user stop $unit.service" "$FAKE_SYSTEMCTL_LOG"
  [ ! -f "$service" ]
  [ ! -f "$timer" ]
  [ ! -e "$clone_dir" ]
  [ -f "$log_dir/kept.log" ]
}

@test 'leaves a folder that is not a scheduled run clone when uninstalling' {
  mkdir -p "$clone_dir"
  touch "$clone_dir/mine.txt"

  run_install --uninstall

  [ "$status" -eq 0 ]
  [ -f "$clone_dir/mine.txt" ]
}
