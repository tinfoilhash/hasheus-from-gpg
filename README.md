# hasheus / from gpg

bridge gpg verified files to nostr — such as bitcoin core, hardware wallet firmware, and more — making them easy to access through a client like [hasheus](https://hasheus.com/).

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

the [scheduled run](scheduled_run/README.md) also needs [git](https://git-scm.com/) and [perl](https://www.perl.org/), and an ai's cli. curl, file, perl, shasum, and xmllint come with macos, and git with its command line tools. gh must be logged in (`gh auth login`, or set `GH_TOKEN`).

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

on the first run, only the last 3 releases of a package are verified. subsequent runs verify up to 30 releases since the previous run. the date/time of the last release verified is stored in `~/.config/hasheus-from-gpg/{{name}}`.

a release whose signature isn't from a listed key (or, for projects that sign each file, a file whose signature isn't) stops that package's run without being recorded, so it's tried again on the next run. so does a github release from the last day that's still missing its hashes or signatures, since projects can publish a release before its files are uploaded; an older one is skipped. a file that fails its hash check or has a bad signature isn't published, but it doesn't block the package: the release's other files are published, the release is recorded so the next run checks later releases, and the run exits 1 so the skipped file is reported. a signature only counts if its key isn't revoked and the signature was made before the key's expiry date. gpg only knows a key's current expiry date, so if a key lapses and its owner extends it, signatures made during the lapse count too.

### dry run

a dry run does everything except publish events and record the last release, so it's safe to run anywhere. any `DRY_RUN` value but `0` means a dry run. it only reads from the relay, so it can take your npub instead of your nsec:

```bash
DRY_RUN=1 NPUB={{npub...}} ./verify_all.sh
```

### scheduled run

[scheduled_run](scheduled_run/README.md) runs every package on a schedule on a mac (daily by default) and has an ai triage the results: it opens issues for upstream maintainers, opens fix prs, and opens an issue with each run's summary. its [readme](scheduled_run/README.md) covers the requirements and settings. to install it:

```bash
./scheduled_run/install.sh
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
