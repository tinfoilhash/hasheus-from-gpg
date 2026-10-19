#!/usr/bin/env bash

# the daily run: updates this clone to main, runs every package for real,
# audits the keys, then has an ai triage the results by following daily_run.md.
# if the ai step fails, it opens a plain summary instead. see the readme to set
# it up.

ai_command="${AI_COMMAND:-claude -p --dangerously-skip-permissions}"
ai_timeout_seconds="${AI_TIMEOUT_SECONDS:-3600}"
log_root="${DAILY_RUN_LOG_DIR:-$HOME/Library/Logs/verify-from-gpg}"
keep_days="${DAILY_RUN_KEEP_DAYS:-30}"

repo_dir=$(dirname -- "$(realpath "$0")")
cd "$repo_dir" || exit 1

# the run resets this clone to main, so only run in a clone set up for it.
check_clone() {
  if [ "$(git config --bool verify-from-gpg.dailyRun)" != true ]; then
    echo 'not a daily run clone (see the readme), exiting'
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
  esac
}

# the repo defaults to origin's, and the account that posts to its owner, so a
# fork's daily run posts to the fork as its owner.
set_github_repo_and_user() {
  github_repo="${DAILY_RUN_GITHUB_REPO:-$(origin_repo)}"

  if [[ ! "$github_repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "origin isn't a github repo, so set DAILY_RUN_GITHUB_REPO, exiting"
    exit 1
  fi

  github_user="${DAILY_RUN_GITHUB_USER:-${github_repo%%/*}}"
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
      echo "another daily run is in progress (pid $pid), exiting"
      exit 1
    fi
  fi

  echo "$$" > "$lock_dir/pid" || exit 1
  trap 'rm -rf "$log_root/.lock"' EXIT
}

# resets to origin's main, undoing anything the last run's ai left behind, then
# runs that version of this script.
update_clone() {
  git fetch -q origin || exit 1
  git checkout -q -f main || exit 1
  git reset -q --hard origin/main || exit 1
  git clean -q -fd || exit 1

  DAILY_RUN_UPDATED=1 exec "$repo_dir/daily_run.sh"
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
  home=$(mktemp -d /tmp/verify-from-gpg-audit.XXXXXX) || exit 1
  GNUPGHOME="$home" ./check_keys.sh --import > "$run_dir/keys-audit.log" 2>&1
  GNUPGHOME="$home" gpgconf --kill gpg-agent 2> /dev/null
  rm -rf "$home"
}

# runs a command, killing it and everything it started if it's still running
# after the given seconds (exiting 124, like `timeout`, which macos doesn't
# have). the command runs in its own process group so the kill reaches the
# commands an ai's cli runs, too.
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

# runs AI_COMMAND (split on spaces) with the prompt appended, without the nsec,
# and with DRY_RUN and the npub, so the package scripts it runs are dry runs. it
# runs as this user, so this guards against mistakes, not a determined ai.
run_ai() {
  local prompt="follow daily_run.md in this repo for the daily run in \
$run_dir, whose issue is \"daily run $run_date\" in $github_repo. you act as \
the github user $github_user."

  local command
  read -r -a command <<< "$ai_command"

  local npub
  npub=$(nak encode npub "$(nak key public "$NSEC" < /dev/null)" < /dev/null)

  env -u NSEC DRY_RUN=1 NPUB="$npub" perl -e "$timeout_program" \
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
    echo "see \`ai.log\` in \`$run_dir\`."
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

  gh issue create --repo "$github_repo" --title "daily run $run_date" \
    --body-file "$body"
}

main() {
  check_clone

  # launchd runs this in a login shell, so the nsec comes from the shell's
  # startup files.
  if [ -z "${NSEC:-}" ]; then
    echo '$NSEC not set, exiting'
    exit 1
  fi

  if [[ ! "$ai_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
    echo "AI_TIMEOUT_SECONDS must be a whole number of seconds, exiting"
    exit 1
  fi

  take_lock

  if [ -z "${DAILY_RUN_UPDATED:-}" ]; then
    update_clone
  fi

  # keep the mac awake until the run ends.
  if command -v caffeinate > /dev/null; then
    caffeinate -i -w "$$" &
  fi

  # always post as the run's account, whichever one gh has active.
  set_github_repo_and_user
  GH_TOKEN=$(gh auth token --user "$github_user") || exit 1
  export GH_TOKEN

  run_date=$(date +%Y-%m-%d)
  run_dir="$log_root/$(date +%Y-%m-%d-%H%M%S)"
  mkdir -p "$run_dir" || exit 1

  delete_old_runs
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
