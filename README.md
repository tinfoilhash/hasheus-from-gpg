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

curl, file, shasum, and xmllint come with macos.

### import gpg keys

you must manually import the gpg keys of the authors. each `verify.sh` script checks for the expected fingerprint(s) and includes the last known url(s).

for example:

```bash
curl https://keybase.io/craigraw/pgp_keys.asc | gpg --import
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
