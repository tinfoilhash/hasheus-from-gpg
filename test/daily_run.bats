#!/usr/bin/env bats

# runs daily_run.sh in a clone of a scratch repo that has the real daily run
# files and stub verify_all.sh and check_keys.sh, so these test the run's own
# steps. the fakes stand in for gh, nak, and the ai's cli.

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

git_quiet() {
  git -c user.name=test -c user.email=test@test -c init.defaultBranch=main \
    "$@" -q
}

# writes the scratch repo: the real daily_run.sh and daily_run.md, a
# verify_all.sh stub that logs each package in $STUB_STATUSES ("<name>
# <status>" per line), and a check_keys.sh stub with one warning (that stops
# before its counts with $STUB_AUDIT_FAILS set).
write_scratch_repo() {
  local work_dir="$1"

  mkdir -p "$work_dir"
  cd "$work_dir" || exit 1
  cp "$PROJECT_DIR/daily_run.sh" "$PROJECT_DIR/daily_run.md" .

  cat > verify_all.sh << 'EOF'
#!/usr/bin/env bash
mkdir -p "$LOG_DIR"
printf '%s\n' "$STUB_STATUSES" > "$LOG_DIR/status.txt"
while read -r name status; do
  echo "--- verifying $name" > "$LOG_DIR/$name.log"
  if [ "$status" -ne 0 ]; then
    echo 'relay query failed, exiting' >> "$LOG_DIR/$name.log"
  fi
done < "$LOG_DIR/status.txt"
EOF
  cat > check_keys.sh << 'EOF'
#!/usr/bin/env bash
echo '  warning: a stub warning'
[ -n "${STUB_AUDIT_FAILS:-}" ] && exit 1
echo '--- 0 problems, 1 warnings'
EOF
  chmod +x verify_all.sh check_keys.sh

  git_quiet init
  git add .
  git_quiet commit -m 'scratch repo'
}

setup() {
  local work_dir="$BATS_TEST_TMPDIR/work"
  write_scratch_repo "$work_dir"

  origin_dir="$BATS_TEST_TMPDIR/origin.git"
  clone_dir="$BATS_TEST_TMPDIR/clone"
  git_quiet clone --bare "$work_dir" "$origin_dir"
  git_quiet clone "$origin_dir" "$clone_dir"
  git -C "$clone_dir" config verify-from-gpg.dailyRun true

  export PATH="$PROJECT_DIR/test/fakes:$PATH"
  export DAILY_RUN_LOG_DIR="$BATS_TEST_TMPDIR/logs"
  export NSEC='nsec-fake'
  export FAKE_GH_ROOT="$BATS_TEST_TMPDIR/gh"
  export FAKE_GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  export FAKE_AI_LOG="$BATS_TEST_TMPDIR/ai.log"
  export AI_COMMAND='ai'
  export STUB_STATUSES='good 0'
  mkdir -p "$FAKE_GH_ROOT"
  : > "$FAKE_GH_LOG"
}

run_daily() {
  run "$clone_dir/daily_run.sh"
}

# the run directory of the most recent run.
last_run_dir() {
  find "$DAILY_RUN_LOG_DIR" -mindepth 1 -maxdepth 1 -type d -name '20*' \
    | sort | tail -n 1
}

@test 'refuses to run in a clone not set up for daily runs' {
  git -C "$clone_dir" config --unset verify-from-gpg.dailyRun

  run_daily

  [ "$status" -eq 1 ]
  [[ "$output" == *'not a daily run clone'* ]]
  [ ! -f "$FAKE_AI_LOG" ]
}

@test 'exits when the nsec is not set' {
  unset NSEC

  run_daily

  [ "$status" -eq 1 ]
  [[ "$output" == *'$NSEC not set, exiting'* ]]
  [ ! -f "$FAKE_AI_LOG" ]
}

@test 'takes over the lock from a run that was killed' {
  mkdir -p "$DAILY_RUN_LOG_DIR/.lock"
  sleep 0 &
  local dead_pid=$!
  wait "$dead_pid"
  echo "$dead_pid" > "$DAILY_RUN_LOG_DIR/.lock/pid"

  run_daily

  [ "$status" -eq 0 ]
  [ -f "$FAKE_AI_LOG" ]
  [ ! -d "$DAILY_RUN_LOG_DIR/.lock" ]
}

@test 'exits while another run holds the lock' {
  mkdir -p "$DAILY_RUN_LOG_DIR/.lock"
  echo "$$" > "$DAILY_RUN_LOG_DIR/.lock/pid"

  run_daily

  [ "$status" -eq 1 ]
  [[ "$output" == *'another daily run is in progress'* ]]
  [ ! -f "$FAKE_AI_LOG" ]
}

@test 'resets the clone to origin main, undoing what the last ai left' {
  FAKE_AI_TAMPER=1 run_daily
  [ -f "$clone_dir/planted.txt" ]

  run_daily

  [ "$status" -eq 0 ]
  [ ! -e "$clone_dir/tampered.txt" ]
  [ ! -e "$clone_dir/planted.txt" ]
  [ "$(git -C "$clone_dir" rev-parse HEAD)" = \
    "$(git -C "$origin_dir" rev-parse main)" ]
}

@test 'runs AI_COMMAND with the prompt, without the nsec, as a dry run' {
  AI_COMMAND='ai --model test-model' run_daily

  [ "$status" -eq 0 ]
  grep -q "^args: --model test-model follow daily_run.md .* \"daily run \
$(date +%Y-%m-%d)\" in tinfoilhash/verify-from-gpg.$" "$FAKE_AI_LOG"
  grep -q '^env: NSEC=unset DRY_RUN=1 NPUB=npub-for-' "$FAKE_AI_LOG"
}

@test 'runs claude by default' {
  unset AI_COMMAND
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nexec ai claude "$@"\n' \
    > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_daily

  [ "$status" -eq 0 ]
  grep -q '^args: claude -p --dangerously-skip-permissions follow ' \
    "$FAKE_AI_LOG"
}

@test 'stops a hung ai and everything it started, then opens a plain summary' {
  local child_pid_file="$BATS_TEST_TMPDIR/child.pid"

  AI_TIMEOUT_SECONDS=1 FAKE_AI_HANG="$child_pid_file" run_daily

  [ "$status" -eq 0 ]
  grep -q '^the ai step failed (exit 124)' "$FAKE_GH_ROOT/created-100.md"
  ! kill -0 "$(cat "$child_pid_file")" 2> /dev/null || false
}

@test 'refuses a timeout that is not a whole number of seconds' {
  AI_TIMEOUT_SECONDS=1.5 run_daily

  [ "$status" -eq 1 ]
  [[ "$output" == *'AI_TIMEOUT_SECONDS must be a whole number'* ]]
  [ ! -f "$FAKE_AI_LOG" ]
}

@test 'leaves the daily issue to the ai when it succeeds' {
  run_daily

  [ "$status" -eq 0 ]
  [ "$(grep -c '^create ' "$FAKE_GH_LOG")" -eq 0 ]
}

@test 'opens a plain summary as the configured user when the ai fails' {
  STUB_STATUSES=$'good 0\nflaky 1' FAKE_AI_STATUS=3 run_daily

  [ "$status" -eq 0 ]
  grep -q "^create tinfoilhash/verify-from-gpg daily run $(date +%Y-%m-%d) \
(token-for-tinfoilhash)$" "$FAKE_GH_LOG"
  grep -q '^the ai step failed (exit 3)' "$FAKE_GH_ROOT/created-100.md"
  grep -q '^- \*\*flaky\*\* (exit 1): relay query failed, exiting$' \
    "$FAKE_GH_ROOT/created-100.md"
  grep -q '^  warning: a stub warning$' "$FAKE_GH_ROOT/created-100.md"
}

@test 'says so in the plain summary when the key audit did not finish' {
  STUB_AUDIT_FAILS=1 FAKE_AI_STATUS=3 run_daily

  [ "$status" -eq 0 ]
  grep -q "^the key audit didn't finish" "$FAKE_GH_ROOT/created-100.md"
}

@test 'deletes runs older than DAILY_RUN_KEEP_DAYS' {
  local old_dir="$DAILY_RUN_LOG_DIR/2025-01-01-090000"
  mkdir -p "$old_dir"
  touch -t 202501010900 "$old_dir"

  run_daily

  [ "$status" -eq 0 ]
  [ ! -d "$old_dir" ]
  [ -n "$(last_run_dir)" ]
}
