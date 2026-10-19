#!/usr/bin/env bats

# runs install_daily_run.sh from a scratch checkout whose origin is a local
# repo, with HOME in a temp directory and the fake launchctl.

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

label='com.tinfoilhash.verify-from-gpg.daily'

git_quiet() {
  git -c user.name=test -c user.email=test@test -c init.defaultBranch=main \
    "$@" -q
}

setup() {
  local work_dir="$BATS_TEST_TMPDIR/work"
  mkdir -p "$work_dir/launchd"
  cp "$PROJECT_DIR/install_daily_run.sh" "$work_dir/"
  cp "$PROJECT_DIR/launchd/$label.plist" "$work_dir/launchd/"
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
  unset DAILY_RUN_CLONE_DIR DAILY_RUN_LOG_DIR NSEC
  mkdir -p "$HOME"
  echo 'export NSEC=nsec-fake' > "$HOME/.bash_profile"

  clone_dir="$HOME/Library/Application Support/verify-from-gpg/repo"
  plist="$HOME/Library/LaunchAgents/$label.plist"
}

run_install() {
  run "$checkout_dir/install_daily_run.sh" "$@"
}

@test 'clones origin into a daily run clone' {
  run_install

  [ "$status" -eq 0 ]
  [ "$(git -C "$clone_dir" config verify-from-gpg.dailyRun)" = true ]
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
  grep -qF "<string>'$clone_dir/daily_run.sh'</string>" "$plist"
  grep -qF "<string>$HOME/Library/Logs/verify-from-gpg/launchd.log</string>" \
    "$plist"
  [ "$(grep -c 'LOGIN_SHELL\|CLONE_DIR\|LOG_DIR' "$plist")" -eq 0 ]
  [ -d "$HOME/Library/Logs/verify-from-gpg" ]
}

@test 'uses DAILY_RUN_CLONE_DIR and DAILY_RUN_LOG_DIR' {
  DAILY_RUN_CLONE_DIR="$BATS_TEST_TMPDIR/my clone" \
    DAILY_RUN_LOG_DIR="$BATS_TEST_TMPDIR/my logs" run_install

  [ "$status" -eq 0 ]
  [ "$(git -C "$BATS_TEST_TMPDIR/my clone" config verify-from-gpg.dailyRun)" \
    = true ]
  grep -qF "'$BATS_TEST_TMPDIR/my clone/daily_run.sh'" "$plist"
  grep -qF "$BATS_TEST_TMPDIR/my logs/launchd.log" "$plist"
}

@test 'loads the job, reloading it on a reinstall' {
  run_install
  FAKE_LAUNCHCTL_LOADED=1 run_install

  [ "$status" -eq 0 ]
  [[ "$output" == *'using the existing clone'* ]]
  [ "$(grep -c "^bootstrap gui/$(id -u) $plist$" "$FAKE_LAUNCHCTL_LOG")" -eq 2 ]
  grep -q "^bootout gui/$(id -u)/$label$" "$FAKE_LAUNCHCTL_LOG"
}

@test 'refuses to use a folder that is not a daily run clone' {
  mkdir -p "$clone_dir"

  run_install

  [ "$status" -eq 1 ]
  [[ "$output" == *"exists but isn't a daily run clone"* ]]
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
  touch "$HOME/Library/Logs/verify-from-gpg/kept.log"

  FAKE_LAUNCHCTL_LOADED=1 run_install --uninstall

  [ "$status" -eq 0 ]
  grep -q "^bootout gui/$(id -u)/$label$" "$FAKE_LAUNCHCTL_LOG"
  [ ! -f "$plist" ]
  [ ! -e "$clone_dir" ]
  [ -f "$HOME/Library/Logs/verify-from-gpg/kept.log" ]
}

@test 'leaves a folder that is not a daily run clone when uninstalling' {
  mkdir -p "$clone_dir"
  touch "$clone_dir/mine.txt"

  run_install --uninstall

  [ "$status" -eq 0 ]
  [ -f "$clone_dir/mine.txt" ]
}
