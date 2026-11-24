#!/usr/bin/env bats

# runs scheduled_run/run.sh in a clone of a scratch repo that has the real
# scheduled run files and stub verify_all.sh and check_keys.sh, so these test
# the run's own steps. the fakes stand in for gh and the ai's cli.

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

git_quiet() {
  git -c user.name=test -c user.email=test@test -c init.defaultBranch=main \
    -c commit.gpgsign=false \
    "$@" -q
}

# writes the scratch repo: the real scheduled_run/run.sh and instructions.md, a
# verify_all.sh stub that logs each package in $STUB_STATUSES ("<name>
# <status>" per line), and a check_keys.sh stub with one warning (that stops
# before its counts with $STUB_AUDIT_FAILS set).
write_scratch_repo() {
  local work_dir="$1"

  mkdir -p "$work_dir"
  cd "$work_dir" || exit 1
  mkdir -p scheduled_run
  cp "$PROJECT_DIR/scheduled_run/run.sh" \
    "$PROJECT_DIR/scheduled_run/instructions.md" scheduled_run/

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
  git -C "$clone_dir" config hasheus-from-gpg.scheduledRun true
  set_origin https://github.com/tinfoilhash/hasheus-from-gpg.git

  export PATH="$PROJECT_DIR/test/fakes:$PATH"
  export SCHEDULED_RUN_LOG_DIR="$BATS_TEST_TMPDIR/logs"
  export HASHEUS_PUBLIC_KEY='npub1fake'
  export HASHEUS_SECRET_KEY='nsec1fake'
  export FAKE_GH_ROOT="$BATS_TEST_TMPDIR/gh"
  export FAKE_GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  export FAKE_AI_LOG="$BATS_TEST_TMPDIR/ai.log"
  export FAKE_INHIBIT_LOG="$BATS_TEST_TMPDIR/inhibit.log"
  export FAKE_TOR_LOG="$BATS_TEST_TMPDIR/tor.log"
  export FAKE_TOR_PID_FILE="$BATS_TEST_TMPDIR/tor.pid"
  # a port nothing listens on, so a tor on this machine isn't used.
  export SCHEDULED_RUN_TOR_PORT=$((40000 + RANDOM % 20000))
  export AI_COMMAND='ai'
  export STUB_STATUSES='good 0'

  # the issue title's time is the run's, so match any.
  run_title="scheduled run $(date +%Y-%m-%d) [0-9][0-9]:[0-9][0-9]"
  mkdir -p "$FAKE_GH_ROOT"
  : > "$FAKE_GH_LOG"
}

# points the clone's origin at a github url, which git maps back to the local
# origin, so the run reads the url but fetches from the scratch repo.
set_origin() {
  local url="$1"

  git -C "$clone_dir" remote set-url origin "$url"
  git -C "$clone_dir" config "url.$origin_dir.insteadOf" "$url"
}

run_scheduled() {
  run "$clone_dir/scheduled_run/run.sh"
}

# the run directory of the most recent run.
last_run_dir() {
  find "$SCHEDULED_RUN_LOG_DIR" -mindepth 1 -maxdepth 1 -type d -name '20*' \
    | sort | tail -n 1
}

@test 'refuses to run in a clone not set up for scheduled runs' {
  git -C "$clone_dir" config --unset hasheus-from-gpg.scheduledRun

  run_scheduled

  [ "$status" -eq 1 ]
  [[ "$output" == *'not a scheduled run clone'* ]]
  [ ! -f "$FAKE_AI_LOG" ]
}

@test 'exits when either key is not set' {
  local variable
  for variable in HASHEUS_PUBLIC_KEY HASHEUS_SECRET_KEY; do
    run env -u "$variable" "$clone_dir/scheduled_run/run.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"\$$variable not set, exiting"* ]]
  done

  [ ! -f "$FAKE_AI_LOG" ]
}

@test 'takes over the lock from a run that was killed' {
  mkdir -p "$SCHEDULED_RUN_LOG_DIR/.lock"
  sleep 0 &
  local dead_pid=$!
  wait "$dead_pid"
  echo "$dead_pid" > "$SCHEDULED_RUN_LOG_DIR/.lock/pid"

  run_scheduled

  [ "$status" -eq 0 ]
  [ -f "$FAKE_AI_LOG" ]
  [ ! -d "$SCHEDULED_RUN_LOG_DIR/.lock" ]
}

@test 'exits while another run holds the lock' {
  mkdir -p "$SCHEDULED_RUN_LOG_DIR/.lock"
  echo "$$" > "$SCHEDULED_RUN_LOG_DIR/.lock/pid"

  run_scheduled

  [ "$status" -eq 1 ]
  [[ "$output" == *'another scheduled run is in progress'* ]]
  [ ! -f "$FAKE_AI_LOG" ]
}

@test 'resets the clone to origin main, undoing what the last ai left' {
  FAKE_AI_TAMPER=1 run_scheduled
  [ -f "$clone_dir/planted.txt" ]

  run_scheduled

  [ "$status" -eq 0 ]
  [ ! -e "$clone_dir/tampered.txt" ]
  [ ! -e "$clone_dir/planted.txt" ]
  [ "$(git -C "$clone_dir" rev-parse HEAD)" = \
    "$(git -C "$origin_dir" rev-parse main)" ]
}

@test 'runs AI_COMMAND with the prompt, without the secret key, as a dry run' {
  AI_COMMAND='ai --model test-model' run_scheduled

  [ "$status" -eq 0 ]
  grep -q "^args: --model test-model follow scheduled_run/instructions.md \
.* \"$run_title\" in tinfoilhash/hasheus-from-gpg. " "$FAKE_AI_LOG"
  grep -q "^env: HASHEUS_SECRET_KEY=unset DRY_RUN=1 \
HASHEUS_PUBLIC_KEY=npub1fake$" "$FAKE_AI_LOG"
}

@test 'tells the ai the repo and the user it acts as' {
  run_scheduled

  [ "$status" -eq 0 ]
  grep -q "in tinfoilhash/hasheus-from-gpg. you act as the github user \
tinfoilhash.$" "$FAKE_AI_LOG"
}

@test 'posts to a fork as its owner' {
  set_origin git@github.com:someone/hasheus-from-gpg.git

  FAKE_AI_STATUS=3 run_scheduled

  [ "$status" -eq 0 ]
  grep -q "^create someone/hasheus-from-gpg $run_title \
(token-for-someone)$" "$FAKE_GH_LOG"
}

@test 'posts as SCHEDULED_RUN_GITHUB_USER when set, like for an organization' {
  set_origin https://github.com/some-org/hasheus-from-gpg.git

  SCHEDULED_RUN_GITHUB_USER=someone FAKE_AI_STATUS=3 run_scheduled

  [ "$status" -eq 0 ]
  grep -q "^create some-org/hasheus-from-gpg $run_title \
(token-for-someone)$" "$FAKE_GH_LOG"
}

@test 'reads an ssh:// origin' {
  set_origin ssh://git@github.com/someone/hasheus-from-gpg.git

  FAKE_AI_STATUS=3 run_scheduled

  [ "$status" -eq 0 ]
  grep -q "^create someone/hasheus-from-gpg $run_title (token-for-someone)$" \
    "$FAKE_GH_LOG"
}

@test 'posts to SCHEDULED_RUN_GITHUB_REPO when set' {
  SCHEDULED_RUN_GITHUB_REPO=elsewhere/mirror FAKE_AI_STATUS=3 run_scheduled

  [ "$status" -eq 0 ]
  grep -q "^create elsewhere/mirror $run_title (token-for-elsewhere)$" \
    "$FAKE_GH_LOG"
}

@test 'exits when origin is not on github and no repo is set' {
  set_origin https://gitlab.com/someone/hasheus-from-gpg.git

  run_scheduled

  [ "$status" -eq 1 ]
  [[ "$output" == *"origin isn't a github repo"* ]]
  [ ! -f "$FAKE_AI_LOG" ]
}

@test 'runs claude by default' {
  unset AI_COMMAND
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nexec ai claude "$@"\n' \
    > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_scheduled

  [ "$status" -eq 0 ]
  grep -q '^args: claude -p --dangerously-skip-permissions follow ' \
    "$FAKE_AI_LOG"
}

@test 'keeps the computer from sleeping until the run ends' {
  run_scheduled

  [ "$status" -eq 0 ]
  grep -q -- '--what=sleep:idle .* tail --pid=[0-9]* -f /dev/null$' \
    "$FAKE_INHIBIT_LOG"
  [[ "$output" != *"couldn't take a sleep lock"* ]]
}

@test 'warns when logind refuses the sleep lock, and runs anyway' {
  FAKE_INHIBIT_DENIED=1 run_scheduled

  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: couldn't take a sleep lock"* ]]
  grep -q '^args: ' "$FAKE_AI_LOG"
}

@test 'starts tor for the run and stops it at the end' {
  run_scheduled

  [ "$status" -eq 0 ]
  [[ "$output" == *"started tor on port $SCHEDULED_RUN_TOR_PORT"* ]]
  grep -qF -- "--SocksPort 127.0.0.1:$SCHEDULED_RUN_TOR_PORT" "$FAKE_TOR_LOG"
  grep -qF -- "--DataDirectory $SCHEDULED_RUN_LOG_DIR/.tor " "$FAKE_TOR_LOG"
  grep -q 'Bootstrapped 100%' "$(last_run_dir)/tor.log"
  ! kill -0 "$(cat "$FAKE_TOR_PID_FILE")" 2> /dev/null || false
}

# listens on $SCHEDULED_RUN_TOR_PORT until the test ends, answering each
# connection's first bytes like a socks5 proxy (`socks`) or a web server
# (`http`), and sets listener_pid. (the socks reply has a nul byte, which an
# argument can't hold, so perl writes it.)
listen_on_tor_port() {
  local kind="$1"

  perl -MIO::Socket::INET -e '
    my ($port, $kind) = @ARGV;
    my $reply = $kind eq "socks" ? "\x05\x00" : "HTTP/1.0 400 Bad Request\r\n";
    my $server = IO::Socket::INET->new(LocalAddr => "127.0.0.1",
      LocalPort => $port, Listen => 5, ReuseAddr => 1)
      or die "listen failed: $!\n";
    while (my $client = $server->accept) {
      my $request;
      sysread($client, $request, 3);
      syswrite($client, $reply);
      close $client;
    }
  ' "$SCHEDULED_RUN_TOR_PORT" "$kind" 3> /dev/null &
  listener_pid=$!

  local tries=0
  until (: < "/dev/tcp/127.0.0.1/$SCHEDULED_RUN_TOR_PORT") 2> /dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 50 ]
    sleep 0.1
  done
}

@test 'uses a tor proxy that is already running' {
  listen_on_tor_port socks

  run_scheduled
  kill "$listener_pid"

  [ "$status" -eq 0 ]
  [[ "$output" == *'using the tor proxy already on port'* ]]
  [ ! -f "$FAKE_TOR_LOG" ]
}

@test 'warns when something other than a socks proxy is on the tor port' {
  listen_on_tor_port http

  run_scheduled
  kill "$listener_pid"

  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't a socks proxy is on port"* ]]
  [ ! -f "$FAKE_TOR_LOG" ]
  grep -q '^args: ' "$FAKE_AI_LOG"
}

@test 'warns when it cannot set up tor, and runs anyway' {
  mkdir -p "$SCHEDULED_RUN_LOG_DIR"
  touch "$SCHEDULED_RUN_LOG_DIR/.tor"

  run_scheduled

  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: couldn't set up"* ]]
  [ ! -f "$FAKE_TOR_LOG" ]
  grep -q '^args: ' "$FAKE_AI_LOG"
}

@test 'warns when tor exits before connecting, and runs anyway' {
  FAKE_TOR_FAILS=1 run_scheduled

  [ "$status" -eq 0 ]
  [[ "$output" == *'warning: tor exited before connecting'* ]]
  grep -q 'Could not bind' "$(last_run_dir)/tor.log"
  grep -q '^args: ' "$FAKE_AI_LOG"
}

@test 'refuses a tor port that is not a port number' {
  SCHEDULED_RUN_TOR_PORT=70000 run_scheduled

  [ "$status" -eq 1 ]
  [[ "$output" == *'SCHEDULED_RUN_TOR_PORT must be a port number'* ]]
  [ ! -f "$FAKE_AI_LOG" ]
}

@test 'stops a hung ai and everything it started, even what ignores SIGTERM' {
  local child_pid_file="$BATS_TEST_TMPDIR/child.pid"

  AI_TIMEOUT_SECONDS=1 FAKE_AI_HANG="$child_pid_file" run_scheduled

  [ "$status" -eq 0 ]
  grep -q '^the ai step failed (exit 124)' "$FAKE_GH_ROOT/created-100.md"
  ! kill -0 "$(cat "$child_pid_file")" 2> /dev/null || false
}

@test 'refuses a timeout that is not a whole number of seconds' {
  AI_TIMEOUT_SECONDS=1.5 run_scheduled

  [ "$status" -eq 1 ]
  [[ "$output" == *'AI_TIMEOUT_SECONDS must be a whole number'* ]]
  [ ! -f "$FAKE_AI_LOG" ]
}

@test 'leaves the issue to the ai when it succeeds' {
  run_scheduled

  [ "$status" -eq 0 ]
  [ "$(grep -c '^create ' "$FAKE_GH_LOG")" -eq 0 ]
}

@test 'opens a plain summary as the configured user when the ai fails' {
  STUB_STATUSES=$'good 0\nflaky 1' FAKE_AI_STATUS=3 run_scheduled

  [ "$status" -eq 0 ]
  grep -q "^create tinfoilhash/hasheus-from-gpg $run_title \
(token-for-tinfoilhash)$" "$FAKE_GH_LOG"
  grep -q '^the ai step failed (exit 3)' "$FAKE_GH_ROOT/created-100.md"
  grep -q '^- \*\*flaky\*\* (exit 1): relay query failed, exiting$' \
    "$FAKE_GH_ROOT/created-100.md"
  grep -q '^  warning: a stub warning$' "$FAKE_GH_ROOT/created-100.md"
}

@test 'says so in the plain summary when the key audit did not finish' {
  STUB_AUDIT_FAILS=1 FAKE_AI_STATUS=3 run_scheduled

  [ "$status" -eq 0 ]
  grep -q "^the key audit didn't finish" "$FAKE_GH_ROOT/created-100.md"
}

@test 'deletes runs older than SCHEDULED_RUN_KEEP_DAYS' {
  local old_dir="$SCHEDULED_RUN_LOG_DIR/2025-01-01-090000"
  mkdir -p "$old_dir"
  touch -t 202501010900 "$old_dir"

  run_scheduled

  [ "$status" -eq 0 ]
  [ ! -d "$old_dir" ]
  [ -n "$(last_run_dir)" ]
}
