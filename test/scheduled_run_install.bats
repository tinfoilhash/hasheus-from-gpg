#!/usr/bin/env bats

# runs scheduled_run/install.sh from a scratch checkout whose origin is a local
# repo, with HOME in a temp directory and the fake launchctl.

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

label='com.hasheus.from-gpg.scheduled-run'

git_quiet() {
  git -c user.name=test -c user.email=test@test -c init.defaultBranch=main \
    "$@" -q
}

setup() {
  local work_dir="$BATS_TEST_TMPDIR/work"
  mkdir -p "$work_dir/scheduled_run"
  cp "$PROJECT_DIR/scheduled_run/install.sh" \
    "$PROJECT_DIR/scheduled_run/launchd.plist" "$work_dir/scheduled_run/"
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
  export FAKE_LAUNCHCTL_LOG="$BATS_TEST_TMPDIR/launchctl.log"
  unset SCHEDULED_RUN_CLONE_DIR SCHEDULED_RUN_LOG_DIR SCHEDULED_RUN_HOURS \
    SCHEDULED_RUN_WEEKDAYS NSEC
  mkdir -p "$HOME"
  echo 'export NSEC=nsec-fake' > "$HOME/.bash_profile"

  clone_dir="$HOME/Library/Application Support/hasheus-from-gpg/repo"
  plist="$HOME/Library/LaunchAgents/$label.plist"
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

@test 'writes the plist with the shell and paths filled in' {
  run_install

  [ "$status" -eq 0 ]
  plutil -lint "$plist" > /dev/null 2>&1 || ! command -v plutil > /dev/null
  grep -q '<string>/bin/bash</string>' "$plist"
  grep -qF "<string>'$clone_dir/scheduled_run/run.sh'</string>" "$plist"
  grep -qF "<string>$HOME/Library/Logs/hasheus-from-gpg/launchd.log</string>" \
    "$plist"
  [ "$(grep -c 'LOGIN_SHELL\|CLONE_DIR\|LOG_DIR' "$plist")" -eq 0 ]
  [ -d "$HOME/Library/Logs/hasheus-from-gpg" ]
}

@test 'uses SCHEDULED_RUN_CLONE_DIR and SCHEDULED_RUN_LOG_DIR' {
  SCHEDULED_RUN_CLONE_DIR="$BATS_TEST_TMPDIR/my clone" \
    SCHEDULED_RUN_LOG_DIR="$BATS_TEST_TMPDIR/my logs" run_install

  [ "$status" -eq 0 ]
  local is_marked
  is_marked=$(git -C "$BATS_TEST_TMPDIR/my clone" config \
    hasheus-from-gpg.scheduledRun)
  [ "$is_marked" = true ]
  grep -qF "'$BATS_TEST_TMPDIR/my clone/scheduled_run/run.sh'" "$plist"
  grep -qF "$BATS_TEST_TMPDIR/my logs/launchd.log" "$plist"
}

# prints the plist's calendar entries as "<weekday> <hour>" lines, with "-" for
# no weekday.
schedule_of() {
  awk '
    /^<dict>/ { weekday = "-" }
    /<key>Weekday<\/key>/ {
      weekday = $0
      gsub(/.*<integer>|<\/integer>.*/, "", weekday)
    }
    /<key>Hour<\/key>/ {
      hour = $0
      gsub(/.*<integer>|<\/integer>.*/, "", hour)
      print weekday, hour
    }
  ' "$plist"
}

@test 'schedules 9:00 every day by default' {
  run_install

  [ "$status" -eq 0 ]
  [ "$(schedule_of)" = '- 9' ]
  [[ "$output" == *'at 9:00 every day'* ]]
}

@test 'schedules each of SCHEDULED_RUN_HOURS, like every 4 hours' {
  SCHEDULED_RUN_HOURS=1,5,9,13,17,21 run_install

  [ "$status" -eq 0 ]
  [ "$(schedule_of | tr '\n' ' ')" = '- 1 - 5 - 9 - 13 - 17 - 21 ' ]
}

@test 'schedules only SCHEDULED_RUN_WEEKDAYS, like once a week' {
  SCHEDULED_RUN_HOURS=9,18 SCHEDULED_RUN_WEEKDAYS=1,5 run_install

  [ "$status" -eq 0 ]
  plutil -lint "$plist" > /dev/null 2>&1 || ! command -v plutil > /dev/null
  [ "$(schedule_of | tr '\n' ' ')" = '1 9 5 9 1 18 5 18 ' ]
  [[ "$output" == *'at 9:00, 18:00 on weekdays 1,5'* ]]
}

@test 'refuses hours or weekdays out of range' {
  SCHEDULED_RUN_HOURS=24 run_install
  [ "$status" -eq 1 ]
  [[ "$output" == *'SCHEDULED_RUN_HOURS must be hours from 0 to 23'* ]]

  SCHEDULED_RUN_WEEKDAYS=7 run_install
  [ "$status" -eq 1 ]
  [[ "$output" == *'SCHEDULED_RUN_WEEKDAYS must be days from 0'* ]]
  [ ! -f "$plist" ]
}

@test 'refuses paths that would break the plist or the job' {
  local dir
  for dir in "$BATS_TEST_TMPDIR/a&b" "$BATS_TEST_TMPDIR/it's" \
    'relative/clone'; do
    SCHEDULED_RUN_CLONE_DIR="$dir" run_install

    [ "$status" -eq 1 ]
    [[ "$output" == *'SCHEDULED_RUN_CLONE_DIR must be an absolute path'* ]]
  done

  [ ! -f "$plist" ]
}

@test 'exits when launchd does not load the job' {
  FAKE_LAUNCHCTL_BOOTSTRAP_FAILS=1 run_install

  [ "$status" -eq 1 ]
  [[ "$output" != *'installed'* ]]
}

@test 'warns about NSEC set only in the shell running the install' {
  rm "$HOME/.bash_profile"

  NSEC=nsec-fake run_install

  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: NSEC isn't set"* ]]
}

@test 'loads the job, reloading it on a reinstall' {
  run_install
  FAKE_LAUNCHCTL_LOADED=1 run_install

  [ "$status" -eq 0 ]
  [[ "$output" == *'using the existing clone'* ]]
  [ "$(grep -c "^bootstrap gui/$(id -u) $plist$" "$FAKE_LAUNCHCTL_LOG")" -eq 2 ]
  grep -q "^bootout gui/$(id -u)/$label$" "$FAKE_LAUNCHCTL_LOG"
}

@test 'refuses to use a folder that is not a scheduled run clone' {
  mkdir -p "$clone_dir"

  run_install

  [ "$status" -eq 1 ]
  [[ "$output" == *"exists but isn't a scheduled run clone"* ]]
  [ ! -f "$plist" ]
}

@test 'warns when the login shell does not set NSEC' {
  rm "$HOME/.bash_profile"

  run_install

  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: NSEC isn't set"* ]]
}

@test 'does not warn when the login shell sets NSEC' {
  run_install

  [ "$status" -eq 0 ]
  [[ "$output" != *'warning'* ]]
}

@test 'uninstalls the job and the clone, keeping the logs' {
  run_install
  touch "$HOME/Library/Logs/hasheus-from-gpg/kept.log"

  FAKE_LAUNCHCTL_LOADED=1 run_install --uninstall

  [ "$status" -eq 0 ]
  grep -q "^bootout gui/$(id -u)/$label$" "$FAKE_LAUNCHCTL_LOG"
  [ ! -f "$plist" ]
  [ ! -e "$clone_dir" ]
  [ -f "$HOME/Library/Logs/hasheus-from-gpg/kept.log" ]
}

@test 'leaves a folder that is not a scheduled run clone when uninstalling' {
  mkdir -p "$clone_dir"
  touch "$clone_dir/mine.txt"

  run_install --uninstall

  [ "$status" -eq 0 ]
  [ -f "$clone_dir/mine.txt" ]
}
