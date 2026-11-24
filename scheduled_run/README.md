# scheduled run

[run.sh](run.sh) runs every package for real on a schedule on linux, with a systemd user timer (daily by default), then has an ai triage the results by following [instructions.md](instructions.md): it opens issues for upstream maintainers, opens prs for bugs in the repo (never merging them), and opens a "scheduled run" issue in the repo with the run's summary. it posts to the repo the clone came from, as that repo's owner, so a fork's scheduled run posts to the fork. if the ai step fails, the script opens a plain summary instead. the ai runs without `HASHEUS_SECRET_KEY` in its environment and with `DRY_RUN` set, so the packages it runs are dry runs. it still runs as you, so this guards against mistakes, not against an ai set on publishing or pushing (it could read the secret key from your shell's startup files, or run code it writes).

## installing

to install it, run this from the root of a checkout of this repo (or your fork):

```bash
./scheduled_run/install.sh
```

that clones the checkout's origin into its own folder, since each run resets its clone to `main`, and installs a systemd user service and timer (`~/.config/systemd/user/hasheus-from-gpg-scheduled-run.{service,timer}`) that run it on the schedule below. a scheduled time missed while the computer was off or asleep runs once it's back, and the run keeps the computer from sleeping until it ends (see [sleep](#sleep)). run it again after changing the schedule or `SCHEDULED_RUN_LOG_DIR`. to move the clone, uninstall first, then set `SCHEDULED_RUN_CLONE_DIR` and install again, so the old clone is removed. to remove the timer and the clone (the logs are kept):

```bash
./scheduled_run/install.sh --uninstall
```

## requirements

systemd starts it in your shell (`$SHELL`) as a login shell, so `HASHEUS_PUBLIC_KEY`, `HASHEUS_SECRET_KEY`, and a `PATH` that finds the tools and the ai's cli have to be set in the files that shell reads at login: `~/.bash_profile` for bash, or `~/.zshenv` or `~/.zprofile` for zsh (not `~/.zshrc`). to check what the job will see:

```bash
env -i HOME="$HOME" "$SHELL" -l -c 'command -v gh hasheus hq jaq shasum claude; echo "${HASHEUS_SECRET_KEY:+secret key set}"'
```

`gh` has to be logged in as the account it posts as, and the ai's cli logged in. it also needs git, perl, and systemd.

systemd stops a user's timers when they log out, so to have it run while you're logged out (or before you log in after a reboot), turn on lingering once:

```bash
loginctl enable-linger
```

### tor

packages that download over tor (ashigaru, so far) need a tor socks proxy, `TOR_PROXY` (default: `socks5h://127.0.0.1:9050`). if one is already running there, like a tor system service, the run uses it. otherwise, if the proxy is on this computer and [tor](https://www.torproject.org/) is installed, the run starts it as you for the run's length (the ai's dry runs included) and stops it at the end, so tor doesn't have to run all the time. tor's data is kept in `.tor` in the log folder between runs, so it connects faster, and each run's tor output is in its folder's `tor.log`. without tor, those packages stop and the run carries on.

### sleep

each run takes a logind lock that keeps the computer from sleeping until it ends. logind only grants it to a run inside a login session, though, so a run that starts while you're logged out logs a warning and goes on without it. that's usually fine, since nothing logged out suspends on idle (closing the lid suspends regardless of the lock). to grant the lock anyway, add a polkit rule, with your user name in place of `{{user}}`:

```bash
sudo tee /etc/polkit-1/rules.d/50-hasheus-from-gpg.rules << 'EOF'
polkit.addRule(function (action, subject) {
  if (action.id == "org.freedesktop.login1.inhibit-block-sleep"
      && subject.user == "{{user}}") {
    return polkit.Result.YES;
  }
});
EOF
```

## running it now

to run it without waiting for the schedule:

```bash
systemctl --user start --no-block hasheus-from-gpg-scheduled-run.service
```

its output (anything before a run's log folder exists, like a missing key) goes to the journal:

```bash
journalctl --user -u hasheus-from-gpg-scheduled-run.service
```

to see when it runs next:

```bash
systemctl --user list-timers hasheus-from-gpg-scheduled-run.timer
```

## settings

it's configured with env vars, set in the same place as the hasheus keys:

- `AI_COMMAND`: the ai's cli and its flags, which the prompt is appended to (default: `claude -p --dangerously-skip-permissions`). for example, `opencode run --auto -m <provider/model>` or `codex exec --full-auto`.
- `AI_TIMEOUT_SECONDS`: how long the ai step can run before it's stopped, along with everything it started (default: 3600).
- `SCHEDULED_RUN_GITHUB_REPO` and `SCHEDULED_RUN_GITHUB_USER`: the repo to post to and the `gh` account to post as (default: the clone's origin and its owner). set the user when an organization owns the repo.
- `SCHEDULED_RUN_HOURS`: the hours to run at, from 0 to 23 (default: `9`). for every 4 hours, `1,5,9,13,17,21`.
- `SCHEDULED_RUN_WEEKDAYS`: the days to run on, from 0 (sunday) to 6 (default: every day). for once a week on mondays, `1`.
- `SCHEDULED_RUN_CLONE_DIR`: where the clone goes (default: `~/.local/share/hasheus-from-gpg/repo`, or under `XDG_DATA_HOME` if set). like `SCHEDULED_RUN_LOG_DIR`, it has to be an absolute path, without `'`, `"`, `\`, `$`, or `%`.
- `TOR_PROXY`: the tor socks proxy that packages downloading over tor use, and that the run starts tor on if it's on this computer and not running (default: `socks5h://127.0.0.1:9050`).
- `SCHEDULED_RUN_LOG_DIR`: where each run's logs go (default: `~/.local/state/hasheus-from-gpg/logs`, or under `XDG_STATE_HOME` if set), kept for `SCHEDULED_RUN_KEEP_DAYS` (default: 30).
