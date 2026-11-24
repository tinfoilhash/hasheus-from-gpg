#!/usr/bin/env bash

# installs the scheduled run: a clone of this checkout's origin that run.sh can
# reset each run, and a systemd user timer that runs it at SCHEDULED_RUN_HOURS
# on SCHEDULED_RUN_WEEKDAYS (9:00 every day by default). with --uninstall,
# removes the timer and the clone, keeping the logs.

data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/hasheus-from-gpg"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hasheus-from-gpg"
clone_dir="${SCHEDULED_RUN_CLONE_DIR:-$data_dir/repo}"
log_root="${SCHEDULED_RUN_LOG_DIR:-$state_dir/logs}"
hours="${SCHEDULED_RUN_HOURS:-9}"
weekdays="${SCHEDULED_RUN_WEEKDAYS:-}"
unit='hasheus-from-gpg-scheduled-run'
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
service="$unit_dir/$unit.service"
timer="$unit_dir/$unit.timer"

# the repo's root, one up from this script's folder.
cd "$(dirname -- "$(dirname -- "$(realpath "$0")")")" || exit 1

# the paths go into the unit's double-quoted values, where systemd expands $
# and %, and into a single-quoted shell command, so allow only absolute paths
# without characters that would break either.
check_path() {
  local name="$1"
  local value="$2"

  if [[ "$value" != /* ]] || [[ "$value" =~ [\'\"\\$%] ]] \
    || [[ "$value" == *$'\n'* ]]; then
    echo "$name must be an absolute path without ' \" \\ \$ or %, exiting"
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

# prints the timer's OnCalendar value, like `Mon,Fri *-*-* 9,18:00:00`: each
# hour, on each weekday if any are set, or every day otherwise.
calendar() {
  local days=''
  local weekday
  for weekday in ${weekdays//,/ }; do
    local names=(Sun Mon Tue Wed Thu Fri Sat)
    days="$days${days:+,}${names[$weekday]}"
  done

  echo "${days:+$days }*-*-* $hours:00:00"
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
  # saved by another credential helper.
  git -C "$clone_dir" config credential.helper ''
  git -C "$clone_dir" config --add credential.helper '!gh auth git-credential'

  echo "cloned $url into $clone_dir"
}

# the service runs run.sh in a login shell, so it gets the hasheus keys and
# PATH from the shell's startup files, with the log folder set so run.sh
# writes where this install made it. its output goes to the journal.
write_units() {
  mkdir -p "$unit_dir" "$log_root" || exit 1

  cat > "$service" << EOF || exit 1
[Unit]
Description=hasheus from gpg scheduled run

[Service]
Type=oneshot
Environment="SCHEDULED_RUN_LOG_DIR=$log_root"
ExecStart="$SHELL" -l -c "'$clone_dir/scheduled_run/run.sh'"
EOF

  # Persistent runs a time that was missed while the computer was off or
  # asleep once it's back.
  cat > "$timer" << EOF || exit 1
[Unit]
Description=hasheus from gpg scheduled run

[Timer]
OnCalendar=$(calendar)
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

# the job only sees what the login shell's startup files set, so check without
# this shell's keys.
check_login_shell() {
  local variable
  for variable in HASHEUS_PUBLIC_KEY HASHEUS_SECRET_KEY; do
    if ! env -u HASHEUS_PUBLIC_KEY -u HASHEUS_SECRET_KEY "$SHELL" -l \
      -c "[ -n \"\${$variable:-}\" ]" < /dev/null > /dev/null 2>&1; then
      echo "warning: $variable isn't set in $SHELL's login startup files, so"
      echo 'the run will exit until it is (see the readme)'
    fi
  done
}

# without lingering, systemd stops the user's timers when they log out.
check_linger() {
  local linger
  linger=$(loginctl show-user "$(id -un)" --property=Linger --value \
    2> /dev/null)

  if [ "$linger" != yes ]; then
    echo "warning: lingering is off, so the timer only runs while you're"
    echo 'logged in. to run it while logged out: loginctl enable-linger'
  fi
}

install() {
  check_path SHELL "$SHELL"
  check_path SCHEDULED_RUN_CLONE_DIR "$clone_dir"
  check_path SCHEDULED_RUN_LOG_DIR "$log_root"
  check_schedule
  set_up_clone
  write_units

  # restart, so a reinstall picks up a changed schedule.
  systemctl --user daemon-reload || exit 1
  systemctl --user enable -q "$unit.timer" || exit 1
  systemctl --user restart "$unit.timer" || exit 1

  echo "installed $timer, which runs the scheduled run $(describe_schedule)"
  check_login_shell
  check_linger
  echo "to run it now: systemctl --user start --no-block $unit.service"
  echo "its output: journalctl --user -u $unit.service"
}

uninstall() {
  systemctl --user disable -q --now "$unit.timer" 2> /dev/null
  # stop a run in progress too, so it doesn't keep going from a clone that's
  # about to be removed.
  systemctl --user stop "$unit.service" 2> /dev/null
  rm -f "$service" "$timer"
  systemctl --user daemon-reload 2> /dev/null
  echo "removed $service and $timer"

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
