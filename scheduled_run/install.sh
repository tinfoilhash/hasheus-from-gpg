#!/usr/bin/env bash

# installs the scheduled run: a clone of this checkout's origin that run.sh can
# reset each run, and a launchd job that runs it at SCHEDULED_RUN_HOURS on
# SCHEDULED_RUN_WEEKDAYS (9:00 every day by default). with --uninstall, removes
# the job and the clone, keeping the logs.

app_support_dir="$HOME/Library/Application Support/hasheus-from-gpg"
clone_dir="${SCHEDULED_RUN_CLONE_DIR:-$app_support_dir/repo}"
log_root="${SCHEDULED_RUN_LOG_DIR:-$HOME/Library/Logs/hasheus-from-gpg}"
hours="${SCHEDULED_RUN_HOURS:-9}"
weekdays="${SCHEDULED_RUN_WEEKDAYS:-}"
label='com.hasheus.hasheus-from-gpg.scheduled-run'
plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"

# the repo's root, one up from this script's folder.
cd "$(dirname -- "$(dirname -- "$(realpath "$0")")")" || exit 1

# the paths go into the plist with sed and into a single-quoted shell command,
# so allow only absolute paths without characters that would break either.
check_path() {
  local name="$1"
  local value="$2"

  if [[ "$value" != /* ]] || [[ "$value" =~ [\'\\\|\&\<\>] ]]; then
    echo "$name must be an absolute path without ' \\ | & < or >, exiting"
    exit 1
  fi
}

check_schedule() {
  local hour='([0-9]|1[0-9]|2[0-3])'

  if [[ ! "$hours" =~ ^$hour(,$hour)*$ ]]; then
    echo 'SCHEDULED_RUN_HOURS must be hours from 0 to 23, like 9 or 1,13,'
    echo 'exiting'
    exit 1
  fi

  if [ -n "$weekdays" ] && [[ ! "$weekdays" =~ ^[0-6](,[0-6])*$ ]]; then
    echo 'SCHEDULED_RUN_WEEKDAYS must be days from 0 (sunday) to 6, like 1 or'
    echo '1,3,5, exiting'
    exit 1
  fi
}

# prints launchd's calendar entries: one per hour, on each weekday if any are
# set, or every day otherwise.
schedule_entries() {
  local hour weekday
  for hour in ${hours//,/ }; do
    if [ -z "$weekdays" ]; then
      echo "<dict><key>Hour</key><integer>$hour</integer>"
      echo "<key>Minute</key><integer>0</integer></dict>"
      continue
    fi

    for weekday in ${weekdays//,/ }; do
      echo "<dict><key>Weekday</key><integer>$weekday</integer>"
      echo "<key>Hour</key><integer>$hour</integer>"
      echo "<key>Minute</key><integer>0</integer></dict>"
    done
  done
}

# describes the schedule, like "at 9:00 on days 1,3".
describe_schedule() {
  local times="${hours//,/:00, }:00"

  if [ -z "$weekdays" ]; then
    echo "at $times every day"
  else
    echo "at $times on weekdays $weekdays (0 is sunday)"
  fi
}

is_scheduled_run_clone() {
  local is_marked
  is_marked=$(git -C "$clone_dir" config --bool hasheus-from-gpg.scheduledRun \
    2> /dev/null)

  [ "$is_marked" = true ]
}

set_up_clone() {
  if [ -e "$clone_dir" ]; then
    if ! is_scheduled_run_clone; then
      echo "$clone_dir exists but isn't a scheduled run clone, exiting"
      exit 1
    fi

    echo "using the existing clone in $clone_dir"
    return
  fi

  local url
  url=$(git config --get remote.origin.url) || {
    echo "this checkout has no origin to clone, exiting"
    exit 1
  }

  mkdir -p "$(dirname -- "$clone_dir")" || exit 1
  git clone -q "$url" "$clone_dir" || exit 1

  git -C "$clone_dir" config hasheus-from-gpg.scheduledRun true
  # gh's credentials, so pushes use the account gh is logged in as, not one
  # saved in the keychain.
  git -C "$clone_dir" config credential.helper ''
  git -C "$clone_dir" config --add credential.helper '!gh auth git-credential'

  echo "cloned $url into $clone_dir"
}

write_plist() {
  mkdir -p "$(dirname -- "$plist")" "$log_root" || exit 1

  local schedule
  schedule=$(schedule_entries)

  # `|` separates sed's fields, so the paths can contain `/` and spaces. the
  # schedule goes through the environment, since awk -v can't take newlines.
  set -o pipefail
  sed -e "s|LOGIN_SHELL|$SHELL|" -e "s|CLONE_DIR|$clone_dir|" \
    -e "s|LOG_DIR|$log_root|g" scheduled_run/launchd.plist \
    | SCHEDULE="$schedule" awk '
      $1 == "SCHEDULE" { print ENVIRON["SCHEDULE"]; next }
      { print }
    ' > "$plist" || exit 1
}

# the job only sees what the login shell's startup files set, so check without
# this shell's NSEC.
check_login_shell() {
  if ! env -u NSEC "$SHELL" -l -c '[ -n "${NSEC:-}" ]' < /dev/null \
    > /dev/null 2>&1; then
    echo "warning: NSEC isn't set in $SHELL's login startup files, so the run"
    echo 'will exit until it is (see the readme)'
  fi
}

install() {
  check_path SHELL "$SHELL"
  check_path SCHEDULED_RUN_CLONE_DIR "$clone_dir"
  check_path SCHEDULED_RUN_LOG_DIR "$log_root"
  check_schedule
  set_up_clone
  write_plist

  # reload, so a reinstall picks up a changed plist.
  launchctl bootout "$domain/$label" 2> /dev/null
  launchctl bootstrap "$domain" "$plist" || exit 1

  echo "installed $plist, which runs the scheduled run $(describe_schedule)"
  check_login_shell
  echo "to run it now: launchctl kickstart $domain/$label"
}

uninstall() {
  launchctl bootout "$domain/$label" 2> /dev/null
  rm -f "$plist"
  echo "removed $plist"

  if is_scheduled_run_clone; then
    rm -rf "$clone_dir"
    echo "removed $clone_dir"
  fi

  echo "kept the logs in $log_root"
}

case "${1:-}" in
  '') install ;;
  --uninstall) uninstall ;;
  *)
    echo "usage: $0 [--uninstall]"
    exit 1
    ;;
esac
