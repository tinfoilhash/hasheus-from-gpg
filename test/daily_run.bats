#!/usr/bin/env bats

# runs daily_run.sh in a clone of a scratch repo that has the real daily run
# files and stub packages, verify_all.sh, and check_keys.sh, so these test the
# run's own steps. the fakes stand in for gh, nak, and the ai's cli.

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

git_quiet() {
  git -c user.name=test -c user.email=test@test -c init.defaultBranch=main \
    "$@" -q
}

# a package stub that records whether it ran with the nsec.
write_stub_package() {
  local package_name="$1"

  mkdir -p "packages/$package_name"
  cat > "packages/$package_name/verify.sh" << EOF
#!/usr/bin/env bash
echo "$package_name NSEC=\${NSEC:-unset}" >> "\$FAKE_RERUN_LOG"
EOF
  chmod +x "packages/$package_name/verify.sh"
}

# writes the scratch repo: the real daily_run.sh and daily_run.md, a
# verify_all.sh stub that logs each package in $STUB_STATUSES ("<name>
# <status>" per line), and a check_keys.sh stub with one warning.
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
EOF
  chmod +x verify_all.sh check_keys.sh

  write_stub_package good
  write_stub_package flaky

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
  export FAKE_RERUN_LOG="$BATS_TEST_TMPDIR/reruns.log"
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

@test 'exits while another run holds the lock' {
  mkdir -p "$DAILY_RUN_LOG_DIR/.lock"
  echo "$$" > "$DAILY_RUN_LOG_DIR/.lock/pid"

  run_daily

  [ "$status" -eq 1 ]
  [[ "$output" == *'another daily run is in progress'* ]]
  [ ! -f "$FAKE_AI_LOG" ]
}

@test 'resets the clone to origin main before running' {
  echo 'local change' > "$clone_dir/stray.txt"
  git -C "$clone_dir" add stray.txt
  git_quiet -C "$clone_dir" commit -m 'stray'

  run_daily

  [ "$status" -eq 0 ]
  [ ! -f "$clone_dir/stray.txt" ]
  [ "$(git -C "$clone_dir" rev-parse HEAD)" = \
    "$(git -C "$origin_dir" rev-parse main)" ]
}

@test 'runs the chosen harness without the nsec, as a dry run' {
  AI_HARNESS=codex AI_MODEL=gpt-test run_daily

  [ "$status" -eq 0 ]
  grep -q '^codex exec .*--model gpt-test ' "$FAKE_AI_LOG"
  grep -q '^env: NSEC=unset DRY_RUN=1 NPUB=npub-for-' "$FAKE_AI_LOG"
}

@test 'opens a daily run issue from the summary as the configured user' {
  run_daily

  [ "$status" -eq 0 ]
  grep -q "^create tinfoilhash/verify-from-gpg daily run $(date +%Y-%m-%d) \
(token-for-tinfoilhash)$" "$FAKE_GH_LOG"
  grep -q '^fake summary$' "$FAKE_GH_ROOT/created-100.md"
  grep -q "^<!-- run: $(basename "$(last_run_dir)") -->$" \
    "$FAKE_GH_ROOT/created-100.md"
}

@test 'reruns only transient packages in this repo, with the nsec' {
  STUB_STATUSES=$'good 0\nflaky 1' \
    FAKE_AI_TRANSIENT=$'flaky\n../flaky\nmissing' run_daily

  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_RERUN_LOG")" = 'flaky NSEC=nsec-fake' ]
  grep -q '^- flaky: exit 0$' "$FAKE_GH_ROOT/created-100.md"
}

@test 'opens no issue on a quiet day, and closes finished daily issues' {
  echo '[{"number": 7, "body": "<!-- run: 2026-01-01-090000 -->"}]' \
    > "$FAKE_GH_ROOT/issues.json"

  FAKE_AI_ACTION=quiet run_daily

  [ "$status" -eq 0 ]
  [ "$(grep -c '^create ' "$FAKE_GH_LOG")" -eq 0 ]
  grep -q '^close tinfoilhash/verify-from-gpg#7 ' "$FAKE_GH_LOG"
}

@test 'keeps a daily issue open while it has drafts waiting for approval' {
  mkdir -p "$DAILY_RUN_LOG_DIR/2026-01-01-090000/drafts"
  echo '{"repo": "a/b", "title": "t", "body": "b"}' \
    > "$DAILY_RUN_LOG_DIR/2026-01-01-090000/drafts/1.json"
  echo '[{"number": 7, "body": "<!-- run: 2026-01-01-090000 -->"}]' \
    > "$FAKE_GH_ROOT/issues.json"

  run_daily

  [ "$status" -eq 0 ]
  [ "$(grep -c '^close ' "$FAKE_GH_LOG")" -eq 0 ]
  grep -q "draft 1: $DAILY_RUN_LOG_DIR/2026-01-01-090000/drafts/1.json" \
    "$(last_run_dir)/pending-drafts.txt"
}

@test 'opens a plain summary when the ai step fails' {
  STUB_STATUSES=$'good 0\nflaky 1' FAKE_AI_ACTION=fail run_daily

  [ "$status" -eq 0 ]
  grep -q '^the ai step failed (exit 3)' "$FAKE_GH_ROOT/created-100.md"
  grep -q '^- \*\*flaky\*\* (exit 1): relay query failed, exiting$' \
    "$FAKE_GH_ROOT/created-100.md"
  grep -q '^  warning: a stub warning$' "$FAKE_GH_ROOT/created-100.md"
}

@test 'posts drafts approved by the configured user, and only those' {
  local drafts_dir="$DAILY_RUN_LOG_DIR/2026-01-01-090000/drafts"
  mkdir -p "$drafts_dir"
  echo '{"repo": "up/one", "title": "first", "body": "one"}' \
    > "$drafts_dir/1.json"
  echo '{"repo": "up/two", "issue": 5, "body": "two"}' > "$drafts_dir/2.json"
  echo '{"repo": "up/three", "title": "third", "body": "three"}' \
    > "$drafts_dir/3.json"
  echo '[{"number": 7, "body": "<!-- run: 2026-01-01-090000 -->"}]' \
    > "$FAKE_GH_ROOT/issues.json"
  cat > "$FAKE_GH_ROOT/issue-7.json" << 'EOF'
{"comments": [
  {"author": {"login": "stranger"}, "body": "post all"},
  {"author": {"login": "tinfoilhash"}, "body": "post 1, 2"},
  {"author": {"login": "tinfoilhash"}, "body": "please post 3"}
]}
EOF

  run_daily

  [ "$status" -eq 0 ]
  grep -q '^create up/one first (token-for-tinfoilhash)$' "$FAKE_GH_LOG"
  grep -q '^comment up/two#5 two (token-for-tinfoilhash)$' "$FAKE_GH_LOG"
  [ "$(grep -c 'up/three' "$FAKE_GH_LOG")" -eq 0 ]
  [ -f "$drafts_dir/1.posted" ] && [ -f "$drafts_dir/2.posted" ]
  [ ! -f "$drafts_dir/3.posted" ]
}

@test 'skips drafts the configured user skips' {
  local drafts_dir="$DAILY_RUN_LOG_DIR/2026-01-01-090000/drafts"
  mkdir -p "$drafts_dir"
  echo '{"repo": "up/one", "title": "first", "body": "one"}' \
    > "$drafts_dir/1.json"
  echo '[{"number": 7, "body": "<!-- run: 2026-01-01-090000 -->"}]' \
    > "$FAKE_GH_ROOT/issues.json"
  cat > "$FAKE_GH_ROOT/issue-7.json" << 'EOF'
{"comments": [{"author": {"login": "tinfoilhash"}, "body": "skip all"}]}
EOF

  run_daily

  [ "$status" -eq 0 ]
  [ -f "$drafts_dir/1.skipped" ]
  [ "$(grep -c 'up/one' "$FAKE_GH_LOG")" -eq 0 ]
  grep -q '^close tinfoilhash/verify-from-gpg#7 ' "$FAKE_GH_LOG"
}
