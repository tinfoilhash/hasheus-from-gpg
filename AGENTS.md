# agents

notes for coding agents working in this repo. the [readme](README.md) covers setup and usage; this covers how the code works and what to keep true when changing it.

## what it does

each package script checks a project's new releases: it downloads the release's hash manifest and gpg signatures, verifies the signatures against the package's listed keys, then downloads each file, checks its hash, and publishes a nip-94 (kind 1063) event for it to the relay. the last release checked is recorded so the next run starts after it.

## layout

- `common/common.sh`: shared steps (dependency and key checks, state, signature verification, relay queries, publishing, downloads).
- `common/github.sh`: the flow for packages that publish on github releases (`verify_from_github`).
- `packages/<name>/verify.sh`: one script per package. most are a few lines of config for `verify_from_github`; bitcoin core and coldcard have their own flows.
- `verify_all.sh`: runs every package script.
- `check_keys.sh`: audits the listed keys, and imports them with `--import`.
- `test/`: the [bats](https://github.com/bats-core/bats-core) suite, with fake `gh`, `nak`, and `curl` in `test/fakes`.
- `.github/workflows/`: `test.yml` (lint and tests on macos and ubuntu) and `monitor.yml` (a daily key audit and dry run).

## running scripts

- a real run publishes events to the relay under the nsec's identity, so don't run one unless asked. check changes with a dry run instead, which publishes and records nothing:

  ```bash
  DRY_RUN=1 NPUB={{npub...}} ./packages/{{name}}/verify.sh
  ```

- point `XDG_CONFIG_HOME` at a temp directory to check from an empty state (the last 3 releases) without touching the real state in `~/.config/verify-from-gpg`.
- `gh` must be logged in (`gh auth login`, or set `GH_TOKEN`).

## rules the code keeps

- **fail closed.** a release that fails its signature check, or a file that fails its hash check, stops the package's run without being recorded, so it's retried. a download or relay failure does the same. only a release with no manifest or signature file is skipped and recorded.
- **a release is recorded only after all of its files are published or skipped.** never write state before that.
- **a signature counts only if** it's from a listed key (by primary or signing subkey fingerprint), the key isn't revoked, and it was made before the key's expiry date. see `verify_gpg_signature`.
- **remote data is untrusted.** release names and dates come from the projects' sites and apis: pass them to jaq with `--arg`, never interpolate them into a program; never use a release name as a directory (each release downloads into a fresh `mktemp` directory); and validate dates before use (`is_valid_published_at`). the state file is parsed, never sourced.
- **don't hide failures.** split `local x; x=$(…) || exit 1`, since `local x=$(…)` discards the exit status, and use `set -o pipefail` inside a `$(…)` when a pipeline's earlier commands can fail.
- **loops over releases and manifest lines read from fd 3 and 4** (`while read … <&3; do …; done 3<<< "$list"`), so they run in the main shell (`exit` stops the script) and nothing inside can read the list from stdin.

## adding or changing a package

- for a github package, copy an existing script like `packages/sparrow/verify.sh` and set `package_name`, `repo`, the manifest and signature file name patterns (`{{NAME}}` is the release tag, or use a function, like `packages/liana/verify.sh`), and `key_fingerprints`. `package_name` is the name of the package's state file, so a copied script that keeps the old one overwrites that package's state.
- add a test to `test/packages.bats` with a release named the way the project actually names its files, so a typo in a pattern fails.

## keys

- each listed fingerprint has a comment with the https url it's published at, preferably in the project's own repo. check the fingerprint against that file (`gpg --show-keys`) before listing it.
- new keys usually show up as a release that fails its signature check. find who signed it (`gpg --list-packets` shows the issuer), and confirm the key is published by the project before listing it.
- run `./check_keys.sh` after changing a list. `./check_keys.sh --import` imports only the listed key from each url.
- adding a key doesn't recheck releases that were already recorded. to retry one, set the package's state to just before the release's date, then do a real run (files already published are skipped). the state is `~/.config/verify-from-gpg/<package_name>` (under `XDG_CONFIG_HOME` if set), a single line in the release date's format, for example:

  ```
  last_release_published_at='2026-09-14T16:03:50Z'
  ```

## style

- **bash 3.2**, since that's what macos ships: no `mapfile`, associative arrays, `${var,,}`, or other bash 4+ features. ci runs the tests under 3.2 on macos.
- formatting is [shfmt](https://github.com/mvdan/sh), with its settings in `.editorconfig`.
- code and comments fit in 80 columns, except lines with a url. ci checks this, since shfmt doesn't.

## checks

```bash
shfmt -d .
```

```bash
shfmt -f . | tr '\n' '\0' | xargs -0 shellcheck
```

```bash
actionlint
```

```bash
bats test
```

the fakes in `test/fakes` serve fixtures from a directory and record what's published, so tests never touch the network or the relay.
