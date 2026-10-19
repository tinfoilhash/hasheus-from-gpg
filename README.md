# tinfoil hash / verify from gpg

bridge gpg verified files to nostr — such as bitcoin core, coldcard, and more — making them easy to access through a client like [verify](https://verify.tinfoilhash.com/).

in the future, the hope is that the authors of these packages start signing and publishing directly with their own nostr identity. until then, this collection of shell scripts automates the process of verifying their gpg signed files and publishing under a nostr identity you control.

[tinfoil hash](https://njump.to/npub1gm7yl6a9xsnkg2lepuaf4hddv2yvwlun5atxjtye3pu5l0vh5kes8ef4r5) runs this on a daily basis.

## prerequisites

### dependencies

- [bash](https://www.gnu.org/software/bash/) 3.2 or newer (the macos default, so the scripts must stay compatible with it)
- [curl](https://curl.se/)
- [file](https://www.darwinsys.com/file/)
- [gh](https://cli.github.com/)
- [gpg](https://www.gnupg.org/)
- [hq](https://github.com/orf/html-query)
- [jaq](https://github.com/01mf02/jaq)
- [nak](https://github.com/fiatjaf/nak)
- [shasum](https://perldoc.perl.org/shasum)
- [xmllint](https://gnome.pages.gitlab.gnome.org/libxml2/xmllint.html)

the [daily run](#daily-run) also needs [git](https://git-scm.com/) and [perl](https://www.perl.org/), and an ai's cli. curl, file, perl, shasum, and xmllint come with macos, and git with its command line tools. gh must be logged in (`gh auth login`, or set `GH_TOKEN`).

### import gpg keys

each `verify.sh` script lists the fingerprints of the keys it trusts, each with the url it's published at. to import them all from those urls:

```bash
./check_keys.sh --import
```

only the listed key is imported from each url, even when the file has others. without `--import`, it only reports problems: listed keys that aren't imported or are no longer at their url, and keys in a project's key folder that aren't listed (exit status 1). expired keys are reported as warnings, since only their owners can fix them.

a key can be newer on a keyserver than at its listed url. if one is reported as expired, try refreshing it:

```bash
gpg --keyserver hkps://keys.openpgp.org --recv-keys {{fingerprint}}
```

## usage

```bash
NSEC={{nsec...}} ./verify_all.sh
```

to verify an individual package:

```bash
NSEC={{nsec...}} ./packages/{{name}}/verify.sh
```

on the first run, only the last 3 releases of a package are verified. subsequent runs verify up to 30 releases since the previous run. the date/time of the last release verified is stored in `~/.config/verify-from-gpg/{{name}}`.

a release whose signature isn't from a listed key, or whose file fails its hash check, stops that package's run without being recorded, so it's tried again on the next run. a signature only counts if its key isn't revoked and the signature was made before the key's expiry date. gpg only knows a key's current expiry date, so if a key lapses and its owner extends it, signatures made during the lapse count too.

### dry run

a dry run does everything except publish events and record the last release, so it's safe to run anywhere. any `DRY_RUN` value but `0` means a dry run. it only reads from the relay, so it can take your npub instead of your nsec:

```bash
DRY_RUN=1 NPUB={{npub...}} ./verify_all.sh
```

### daily run

`daily_run.sh` runs every package for real each day on a mac, then has an ai triage the results by following [daily_run.md](daily_run.md): it opens issues for upstream maintainers, opens prs for bugs in the repo (never merging them), and opens a "daily run" issue in the repo with the day's summary. it posts to the repo the clone came from, as that repo's owner, so a fork's daily run posts to the fork. if the ai step fails, the script opens a plain summary instead. the ai runs without `NSEC` in its environment and with `DRY_RUN` set, so the packages it runs are dry runs. it still runs as you, so this guards against mistakes, not against an ai set on publishing or pushing (it could read the nsec from your shell's startup files, or run code it writes).

to install it, run this from a checkout of this repo (or your fork):

```bash
./install_daily_run.sh
```

that clones the checkout's origin into its own folder, since each run resets its clone to `main`, and has launchd run it at 9:00 each day (or when the mac wakes). run it again after changing `DAILY_RUN_CLONE_DIR` or `DAILY_RUN_LOG_DIR`. to remove the job and the clone (the logs are kept):

```bash
./install_daily_run.sh --uninstall
```

launchd starts it in your shell (`$SHELL`) as a login shell, so `NSEC` and a `PATH` that finds the tools and the ai's cli have to be set in the files that shell reads at login: `~/.zshenv` or `~/.zprofile` for zsh (not `~/.zshrc`), or `~/.bash_profile` for bash. `gh` has to be logged in as the account it posts as, and the ai's cli logged in. to run it now:

```bash
launchctl kickstart "gui/$(id -u)/com.tinfoilhash.verify-from-gpg.daily"
```

it's configured with env vars, set in the same place as `NSEC`:

- `AI_COMMAND`: the ai's cli and its flags, which the prompt is appended to (default: `claude -p --dangerously-skip-permissions`). for example, `opencode run --auto -m <provider/model>` or `codex exec --full-auto`.
- `AI_TIMEOUT_SECONDS`: how long the ai step can run before it's stopped, along with everything it started (default: 3600).
- `DAILY_RUN_GITHUB_REPO` and `DAILY_RUN_GITHUB_USER`: the repo to post to and the `gh` account to post as (default: the clone's origin and its owner). set the user when an organization owns the repo.
- `DAILY_RUN_CLONE_DIR`: where the clone goes (default: `~/Library/Application Support/verify-from-gpg/repo`).
- `DAILY_RUN_LOG_DIR`: where each run's logs go (default: `~/Library/Logs/verify-from-gpg`), kept for `DAILY_RUN_KEEP_DAYS` (default: 30).

## development

### tests

the tests use [bats](https://github.com/bats-core/bats-core). fake `gh`, `nak`, and `curl` (in `test/fakes`) serve fixtures, and gpg keys are generated for each run, so the tests never touch the network or the relay.

```bash
brew install actionlint bats-core shellcheck shfmt
```

```bash
bats test
```

### linting & formatting

[shfmt](https://github.com/mvdan/sh) formats the scripts, with its settings in `.editorconfig`. [shellcheck](https://www.shellcheck.net/) lints every file shfmt finds, and [actionlint](https://github.com/rhysd/actionlint) lints the workflows, including shellcheck on their scripts.

```bash
shfmt -d .
```

```bash
shfmt -f . | xargs shellcheck
```

```bash
actionlint
```

nothing else checks line length, so ci also fails on lines over 80 characters (lines with a url are exempt):

```bash
{ shfmt -f .; ls .github/workflows/*.yml; } | tr '\n' '\0' | xargs -0 awk 'length > 80 && !/:\/\// { print FILENAME ":" FNR ": over 80 characters"; failed = 1 } END { exit failed }'
```

to fix formatting:

```bash
shfmt -w .
```
