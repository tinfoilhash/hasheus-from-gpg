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

curl, file, shasum, and xmllint come with macos. gh must be logged in (`gh auth login`, or set `GH_TOKEN`).

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

## development

### tests

the tests use [bats](https://github.com/bats-core/bats-core). fake `gh`, `nak`, and `curl` (in `test/fakes`) serve fixtures, and gpg keys are generated for each run, so the tests never touch the network or the relay.

```bash
brew install actionlint bats-core shellcheck shfmt
```

```bash
bats test
```

### monitoring

the [monitor](.github/workflows/monitor.yml) workflow runs `./check_keys.sh --import` and a dry run of every package each day, to catch upstream changes like a new page layout, a new signer, or an expired or removed key. it fails when the key check finds a problem or a release isn't signed by any listed key, and its summary lists the warnings and any files not published yet.

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

to fix formatting:

```bash
shfmt -w .
```
