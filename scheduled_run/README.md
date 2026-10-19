# scheduled run

[run.sh](run.sh) runs every package for real on a schedule on a mac (daily by default), then has an ai triage the results by following [instructions.md](instructions.md): it opens issues for upstream maintainers, opens prs for bugs in the repo (never merging them), and opens a "scheduled run" issue in the repo with the run's summary. it posts to the repo the clone came from, as that repo's owner, so a fork's scheduled run posts to the fork. if the ai step fails, the script opens a plain summary instead. the ai runs without `NSEC` in its environment and with `DRY_RUN` set, so the packages it runs are dry runs. it still runs as you, so this guards against mistakes, not against an ai set on publishing or pushing (it could read the nsec from your shell's startup files, or run code it writes).

## installing

to install it, run this from the root of a checkout of this repo (or your fork):

```bash
./scheduled_run/install.sh
```

that clones the checkout's origin into its own folder, since each run resets its clone to `main`, and has launchd run it on the schedule below (and when the mac wakes, if it was asleep at a scheduled time). run it again after changing the schedule, `SCHEDULED_RUN_CLONE_DIR`, or `SCHEDULED_RUN_LOG_DIR`. to remove the job and the clone (the logs are kept):

```bash
./scheduled_run/install.sh --uninstall
```

## requirements

launchd starts it in your shell (`$SHELL`) as a login shell, so `NSEC` and a `PATH` that finds the tools and the ai's cli have to be set in the files that shell reads at login: `~/.zshenv` or `~/.zprofile` for zsh (not `~/.zshrc`), or `~/.bash_profile` for bash. `gh` has to be logged in as the account it posts as, and the ai's cli logged in. it also needs git and perl, which come with macos (git with its command line tools).

## running it now

to run it without waiting for the schedule:

```bash
launchctl kickstart "gui/$(id -u)/com.tinfoilhash.verify-from-gpg.scheduled-run"
```

## settings

it's configured with env vars, set in the same place as `NSEC`:

- `AI_COMMAND`: the ai's cli and its flags, which the prompt is appended to (default: `claude -p --dangerously-skip-permissions`). for example, `opencode run --auto -m <provider/model>` or `codex exec --full-auto`.
- `AI_TIMEOUT_SECONDS`: how long the ai step can run before it's stopped, along with everything it started (default: 3600).
- `SCHEDULED_RUN_GITHUB_REPO` and `SCHEDULED_RUN_GITHUB_USER`: the repo to post to and the `gh` account to post as (default: the clone's origin and its owner). set the user when an organization owns the repo.
- `SCHEDULED_RUN_HOURS`: the hours to run at, from 0 to 23 (default: `9`). for every 4 hours, `1,5,9,13,17,21`.
- `SCHEDULED_RUN_WEEKDAYS`: the days to run on, from 0 (sunday) to 6 (default: every day). for once a week on mondays, `1`.
- `SCHEDULED_RUN_CLONE_DIR`: where the clone goes (default: `~/Library/Application Support/verify-from-gpg/repo`).
- `SCHEDULED_RUN_LOG_DIR`: where each run's logs go (default: `~/Library/Logs/verify-from-gpg`), kept for `SCHEDULED_RUN_KEEP_DAYS` (default: 30).
