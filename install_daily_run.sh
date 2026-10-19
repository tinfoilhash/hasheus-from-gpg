#!/usr/bin/env bash

# installs the daily run: a clone of this checkout's origin that daily_run.sh
# can reset each run, and a launchd job that runs it at 9:00 each day. with
# --uninstall, removes the job and the clone, keeping the logs.

app_support_dir="$HOME/Library/Application Support/verify-from-gpg"
clone_dir="${DAILY_RUN_CLONE_DIR:-$app_support_dir/repo}"
log_root="${DAILY_RUN_LOG_DIR:-$HOME/Library/Logs/verify-from-gpg}"
label='com.tinfoilhash.verify-from-gpg.daily'
plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"

cd "$(dirname -- "$(realpath "$0")")" || exit 1

is_daily_run_clone() {
  local is_marked
  is_marked=$(git -C "$clone_dir" config --bool verify-from-gpg.dailyRun \
    2> /dev/null)

  [ "$is_marked" = true ]
}

set_up_clone() {
  if [ -e "$clone_dir" ]; then
    if ! is_daily_run_clone; then
      echo "$clone_dir exists but isn't a daily run clone, exiting"
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

  git -C "$clone_dir" config verify-from-gpg.dailyRun true
  # gh's credentials, so pushes use the account gh is logged in as, not one
  # saved in the keychain.
  git -C "$clone_dir" config credential.helper ''
  git -C "$clone_dir" config --add credential.helper '!gh auth git-credential'

  echo "cloned $url into $clone_dir"
}

write_plist() {
  mkdir -p "$(dirname -- "$plist")" "$log_root" || exit 1

  # `|` separates sed's fields, so the paths can contain `/` and spaces.
  sed -e "s|LOGIN_SHELL|$SHELL|" -e "s|CLONE_DIR|$clone_dir|" \
    -e "s|LOG_DIR|$log_root|g" "launchd/$label.plist" > "$plist" || exit 1
}

# the job only sees what the login shell's startup files set.
check_login_shell() {
  if ! "$SHELL" -l -c '[ -n "${NSEC:-}" ]' < /dev/null > /dev/null 2>&1; then
    echo "warning: NSEC isn't set in $SHELL's login startup files, so the run"
    echo 'will exit until it is (see the readme)'
  fi
}

install() {
  set_up_clone
  write_plist

  # reload, so a reinstall picks up a changed plist.
  launchctl bootout "$domain/$label" 2> /dev/null
  launchctl bootstrap "$domain" "$plist" || exit 1

  echo "installed $plist, which runs the daily run at 9:00 each day"
  check_login_shell
  echo "to run it now: launchctl kickstart $domain/$label"
}

uninstall() {
  launchctl bootout "$domain/$label" 2> /dev/null
  rm -f "$plist"
  echo "removed $plist"

  if is_daily_run_clone; then
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
