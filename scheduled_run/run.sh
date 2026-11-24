#!/usr/bin/env bash

# the scheduled run: updates this clone to main, runs every package for real,
# audits the keys, then has an ai triage the results by following
# instructions.md. if the ai step fails, it opens a plain summary instead. see
# the readme to set it up.

ai_command="${AI_COMMAND:-claude -p --dangerously-skip-permissions}"
ai_timeout_seconds="${AI_TIMEOUT_SECONDS:-3600}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hasheus-from-gpg"
log_root="${SCHEDULED_RUN_LOG_DIR:-$state_dir/logs}"
keep_days="${SCHEDULED_RUN_KEEP_DAYS:-30}"
tor_proxy="${TOR_PROXY:-socks5h://127.0.0.1:9050}"
tor_pid=''

# the repo's root, one up from this script's folder.
repo_dir=$(dirname -- "$(dirname -- "$(realpath "$0")")")
cd "$repo_dir" || exit 1

# the run resets this clone to main, so only run in a clone set up for it.
check_clone() {
  if [ "$(git config --bool hasheus-from-gpg.scheduledRun)" != true ]; then
    echo 'not a scheduled run clone (see the readme), exiting'
    exit 1
  fi
}

# prints the github repo (owner/name) that origin points to.
origin_repo() {
  local url
  url=$(git config --get remote.origin.url)
  url="${url%.git}"

  case "$url" in
    https://github.com/*) echo "${url#https://github.com/}" ;;
    git@github.com:*) echo "${url#git@github.com:}" ;;
    ssh://git@github.com/*) echo "${url#ssh://git@github.com/}" ;;
  esac
}

# the repo defaults to origin's, and the account that posts to its owner, so a
# fork's scheduled run posts to the fork as its owner.
set_github_repo_and_user() {
  github_repo="${SCHEDULED_RUN_GITHUB_REPO:-$(origin_repo)}"

  if [[ ! "$github_repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "origin isn't a github repo, so set SCHEDULED_RUN_GITHUB_REPO, exiting"
    exit 1
  fi

  github_user="${SCHEDULED_RUN_GITHUB_USER:-${github_repo%%/*}}"
}

# a stale lock from a run that was killed is taken over, and so is this run's
# own lock after update_clone runs it again (exec keeps the pid).
take_lock() {
  mkdir -p "$log_root" || exit 1

  local lock_dir="$log_root/.lock"

  if ! mkdir "$lock_dir" 2> /dev/null; then
    local pid
    pid=$(cat "$lock_dir/pid" 2> /dev/null)

    if [ -n "$pid" ] && [ "$pid" != "$$" ] && kill -0 "$pid" 2> /dev/null; then
      echo "another scheduled run is in progress (pid $pid), exiting"
      exit 1
    fi
  fi

  echo "$$" > "$lock_dir/pid" || exit 1
  trap clean_up EXIT
  # exit on these, so the EXIT trap stops tor (background commands ignore
  # SIGINT in a script, so a ctrl-c wouldn't reach it).
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

# run by the EXIT trap, which shellcheck doesn't follow.
# shellcheck disable=SC2329
clean_up() {
  # stop the tor that start_tor started, if any.
  if [ -n "$tor_pid" ]; then
    kill "$tor_pid" 2> /dev/null
    wait "$tor_pid" 2> /dev/null
  fi

  rm -rf "$log_root/.lock"
}

# resets to origin's main, undoing anything the last run's ai left behind, then
# runs that version of this script.
update_clone() {
  git fetch -q origin || exit 1
  git checkout -q -f main || exit 1
  git reset -q --hard origin/main || exit 1
  git clean -q -fd || exit 1

  SCHEDULED_RUN_UPDATED=1 exec "$repo_dir/scheduled_run/run.sh"
}

delete_old_runs() {
  find "$log_root" -mindepth 1 -maxdepth 1 -type d -name '20*' \
    -mtime +"$keep_days" -exec rm -rf {} +
}

# imports new packages' keys into the real keyring, then audits the keys in a
# throwaway one, so a stale copy at a key's url isn't hidden by a newer one.
check_keys() {
  ./check_keys.sh --import > "$run_dir/keys-import.log" 2>&1

  local home
  home=$(mktemp -d /tmp/hasheus-from-gpg-audit.XXXXXX) || exit 1
  GNUPGHOME="$home" ./check_keys.sh --import > "$run_dir/keys-audit.log" 2>&1
  GNUPGHOME="$home" gpgconf --kill gpg-agent 2> /dev/null
  rm -rf "$home"
}

# runs a command, killing it and everything it started if it's still running
# after the given seconds (exiting 124, like `timeout`). the command runs in its
# own process group so the kill reaches the commands an ai's cli runs, too.
# coreutils `timeout` isn't enough: it returns as soon as the command exits, so
# a child that ignores SIGTERM would keep running.
timeout_program='
  my $seconds = shift;
  my $pid = fork // die "fork failed: $!\n";
  if (!$pid) { setpgrp(0, 0); exec @ARGV or die "exec failed: $!\n" }
  $SIG{ALRM} = sub {
    kill "TERM", -$pid;
    sleep 5;
    kill "KILL", -$pid;
    exit 124;
  };
  alarm $seconds;
  waitpid $pid, 0;
  exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
'

# runs AI_COMMAND (split on spaces) with the prompt appended, without the secret
# key and with DRY_RUN, so the package scripts it runs are dry runs. it runs as
# this user, so this guards against mistakes, not a determined ai.
run_ai() {
  local prompt="follow scheduled_run/instructions.md in this repo for the \
scheduled run in $run_dir, whose issue is \"$issue_title\" in $github_repo. \
you act as the github user $github_user."

  local command
  read -r -a command <<< "$ai_command"

  env -u HASHEUS_SECRET_KEY DRY_RUN=1 perl -e "$timeout_program" \
    "$ai_timeout_seconds" "${command[@]}" "$prompt" \
    < /dev/null > "$run_dir/ai.log" 2>&1
}

# lists each package that stopped, with the line it stopped on.
stopped_packages() {
  local package_name package_status
  while read -r package_name package_status; do
    [ "$package_status" -eq 0 ] && continue

    local log="$run_dir/packages/$package_name.log"
    local reason
    reason=$(grep -a -E 'exiting$|failed' "$log" | tail -n 1)
    reason="${reason:-no reason logged}"
    echo "- **$package_name** (exit $package_status): $reason"
  done < "$run_dir/packages/status.txt"
}

# opens the day's issue without the ai, so a failed ai step isn't silent.
open_plain_issue() {
  local ai_status="$1"
  local body="$run_dir/issue.md"

  {
    echo "the ai step failed (exit $ai_status), so this is the plain summary."
    echo "see \`ai.log\` in the run's log folder."
    echo
    echo '### stopped'
    echo
    stopped_packages
    echo
    echo '### key audit'
    echo
    grep -E '^  (problem|warning):' "$run_dir/keys-audit.log" \
      || echo 'no problems or warnings'

    # check_keys.sh ends with its counts, so a log without them means the
    # audit itself failed.
    if ! grep -q -- '^--- [0-9]* problems, [0-9]* warnings$' \
      "$run_dir/keys-audit.log"; then
      echo
      echo "the key audit didn't finish. see \`keys-audit.log\`."
    fi
  } > "$body"

  gh issue create --repo "$github_repo" --title "$issue_title" \
    --body-file "$body"
}

# keeps the computer from sleeping until the run ends. logind refuses the lock
# to a run outside a login session (one started while logged out, with
# lingering) unless a polkit rule allows it (see the readme), so say so rather
# than assume it's held. a refused lock exits right away.
keep_awake() {
  systemd-inhibit --what=sleep:idle --who=hasheus-from-gpg \
    --why='scheduled run' tail --pid="$$" -f /dev/null 2> /dev/null &
  local inhibit_pid=$!

  sleep 1
  if ! kill -0 "$inhibit_pid" 2> /dev/null; then
    echo "warning: couldn't take a sleep lock, so the computer may sleep"
    echo 'during the run (see the readme)'
  fi
}

# makes sure the tor proxy that packages downloading over tor use (TOR_PROXY)
# is running. one that's already running is used as is. otherwise, when the
# proxy is on this computer, this starts tor as this user, with its own config
# and a data folder kept between runs (so it connects faster), and waits for it
# to connect. if it can't, packages that need tor stop on their own, so this
# only warns.
start_tor() {
  local proxy_status=0
  check_socks_proxy "$tor_host" "$tor_port" || proxy_status=$?

  if [ "$proxy_status" -eq 0 ]; then
    echo "using the tor proxy already on $tor_host:$tor_port"
    return
  fi

  if [ "$proxy_status" -eq 1 ]; then
    echo "warning: something that isn't a socks proxy is on"
    echo "$tor_host:$tor_port, so packages that need tor will stop"
    return
  fi

  if [ "$tor_host" != 127.0.0.1 ] && [ "$tor_host" != localhost ]; then
    echo "warning: the tor proxy on $tor_host:$tor_port isn't running, so"
    echo 'packages that need it will stop'
    return
  fi

  if ! command -v tor > /dev/null; then
    echo "warning: tor isn't installed or running on $tor_host:$tor_port, so"
    echo 'packages that need it will stop'
    return
  fi

  local tor_dir="$log_root/.tor"
  local tor_log="$run_dir/tor.log"
  # trouble with tor's own files only stops the packages that need tor.
  if ! mkdir -p "$tor_dir" || ! chmod 700 "$tor_dir"; then
    echo "warning: couldn't set up $tor_dir, so packages that need tor will"
    echo 'stop'
    return
  fi

  # an empty config, so a system torrc (which can set a user or data folder
  # only root can use) doesn't apply. tor won't read /dev/null as one.
  local torrc="$tor_dir/torrc"
  if ! : > "$torrc"; then
    echo "warning: couldn't write $torrc, so packages that need tor will stop"
    return
  fi
  tor -f "$torrc" --defaults-torrc "$torrc" --DataDirectory "$tor_dir" \
    --SocksPort "127.0.0.1:$tor_port" --Log 'notice stdout' \
    < /dev/null > "$tor_log" 2>&1 &
  tor_pid=$!

  local waited=0
  until grep -q 'Bootstrapped 100%' "$tor_log"; do
    if ! kill -0 "$tor_pid" 2> /dev/null; then
      tor_pid=''
      echo "warning: tor exited before connecting (see tor.log), so packages"
      echo 'that need it will stop'
      return
    fi

    # a first start, with nothing kept from an earlier run, can take minutes.
    if [ "$waited" -ge 300 ]; then
      echo "warning: tor didn't connect in 5 minutes (see tor.log), so"
      echo 'packages that need it may stop'
      return
    fi

    sleep 1
    waited=$((waited + 1))
  done

  echo "started tor on $tor_host:$tor_port"
}

# checks for a socks5 proxy at <host> <port> by offering it no authentication,
# which tor accepts. exits 0 for a socks5 proxy, 1 for something else (or one
# that doesn't answer in 5 seconds), and 2 when nothing is listening.
check_socks_proxy() {
  local host="$1"
  local port="$2"

  perl -MIO::Socket::INET -e '
    my ($host, $port) = @ARGV;
    my $socket = IO::Socket::INET->new(
      PeerAddr => $host, PeerPort => $port, Timeout => 5) or exit 2;
    local $SIG{ALRM} = sub { exit 1 };
    alarm 5;
    syswrite($socket, "\x05\x01\x00") == 3 or exit 1;
    my $reply = "";
    sysread($socket, $reply, 2) == 2 or exit 1;
    exit($reply eq "\x05\x00" ? 0 : 1);
  ' "$host" "$port"
}

main() {
  check_clone

  # systemd runs this in a login shell, so the keys come from the shell's
  # startup files.
  local variable
  for variable in HASHEUS_PUBLIC_KEY HASHEUS_SECRET_KEY; do
    if [ -z "${!variable:-}" ]; then
      echo "\$$variable not set, exiting"
      exit 1
    fi
  done

  if [[ ! "$ai_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
    echo "AI_TIMEOUT_SECONDS must be a whole number of seconds, exiting"
    exit 1
  fi

  # the same form the packages require (see check_tor_proxy in common.sh).
  local proxy_pattern='^socks5h://([^[:space:]/:]+):([0-9]+)/?$'
  if [[ ! "$tor_proxy" =~ $proxy_pattern ]] \
    || [ "${BASH_REMATCH[2]}" -lt 1 ] \
    || [ "${BASH_REMATCH[2]}" -gt 65535 ]; then
    echo 'TOR_PROXY must be socks5h://<host>:<port>, exiting'
    exit 1
  fi
  tor_host="${BASH_REMATCH[1]}"
  tor_port="${BASH_REMATCH[2]}"

  take_lock

  if [ -z "${SCHEDULED_RUN_UPDATED:-}" ]; then
    update_clone
  fi

  keep_awake

  # always post as the run's account, whichever one gh has active.
  set_github_repo_and_user
  GH_TOKEN=$(gh auth token --user "$github_user") || exit 1
  export GH_TOKEN

  # runs can be hours apart, so the title has the time too.
  issue_title="scheduled run $(date '+%Y-%m-%d %H:%M')"
  run_dir="$log_root/$(date +%Y-%m-%d-%H%M%S)"
  mkdir -p "$run_dir" || exit 1

  delete_old_runs
  # tor runs until the end, since the ai's dry runs may need it too.
  start_tor
  check_keys
  LOG_DIR="$run_dir/packages" ./verify_all.sh

  local ai_status=0
  run_ai || ai_status=$?

  if [ "$ai_status" -ne 0 ]; then
    open_plain_issue "$ai_status"
  fi
}

# in braces, so bash has read it all before update_clone replaces this file.
{
  main "$@"
  exit
}
