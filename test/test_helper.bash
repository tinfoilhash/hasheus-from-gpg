# shellcheck shell=bash

PROJECT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

gpg_quiet() {
  gpg -q --batch --pinentry-mode loopback --passphrase '' --yes "$@" 2> /dev/null
}

# creates throwaway keys: "signer" and "other" (listed by tests), "stranger" (in the keyring but not listed), and
# "missing" (kept in a separate keyring, so its signatures can't be checked). each key signs with a subkey.
setup_keyring() {
  # gpg-agent's socket path has a short length limit, so keep the keyrings out of the long default temp directory.
  GNUPGHOME=$(mktemp -d /tmp/verify-from-gpg-test.XXXXXX)
  MISSING_GNUPGHOME=$(mktemp -d /tmp/verify-from-gpg-test.XXXXXX)
  export GNUPGHOME MISSING_GNUPGHOME

  local name
  for name in signer other stranger missing; do
    local home="$GNUPGHOME"
    [ "$name" = missing ] && home="$MISSING_GNUPGHOME"

    GNUPGHOME="$home" gpg_quiet --quick-gen-key "$name@test" ed25519 cert never
    GNUPGHOME="$home" gpg_quiet --quick-add-key "$(GNUPGHOME="$home" fingerprint_of "$name")" ed25519 sign never
  done
}

teardown_keyring() {
  # an empty GNUPGHOME means the default keyring, so never stop its agent.
  GNUPGHOME="${GNUPGHOME:?}" gpgconf --kill gpg-agent
  GNUPGHOME="${MISSING_GNUPGHOME:?}" gpgconf --kill gpg-agent
  rm -rf "${GNUPGHOME:?}" "${MISSING_GNUPGHOME:?}"
}

fingerprint_of() {
  local name="$1"

  gpg --with-colons --list-keys "$name@test" | awk -F: '/^fpr/ { print $10; exit }'
}

signing_subkey_of() {
  local name="$1"

  gpg --with-colons --list-keys "$name@test" | awk -F: '/^fpr/ { count++ } /^fpr/ && count == 2 { print $10 }'
}

home_of() {
  local name="$1"

  if [ "$name" = missing ]; then
    echo "$MISSING_GNUPGHOME"
  else
    echo "$GNUPGHOME"
  fi
}

# writes a detached signature, or several concatenated into one file when given several signers.
sign_detached() {
  local signers="$1"
  local data_filename="$2"
  local signature_filename="$3"

  : > "$signature_filename"

  local name
  for name in $signers; do
    GNUPGHOME="$(home_of "$name")" gpg_quiet -u "$name@test" --detach-sign -o - "$data_filename" >> "$signature_filename"
  done
}

sign_clear() {
  local name="$1"
  local data_filename="$2"
  local signed_filename="$3"

  GNUPGHOME="$(home_of "$name")" gpg_quiet -u "$name@test" --clearsign -o "$signed_filename" "$data_filename"
}

# copies common/ (and a package, if given) into a scratch repo, with the fakes first on PATH.
create_repo() {
  local package_name="${1:-}"

  repo_dir="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo_dir/packages"
  cp -R "$PROJECT_DIR/common" "$repo_dir/"

  if [ -n "$package_name" ]; then
    cp -R "$PROJECT_DIR/packages/$package_name" "$repo_dir/packages/"
  fi

  export PATH="$PROJECT_DIR/test/fakes:$PATH"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export NSEC='nsec-fake'
  export FAKE_NAK_LOG="$BATS_TEST_TMPDIR/published"
}

# replaces a package script's key fingerprints with the given ones.
set_key_fingerprints() {
  local package_name="$1"
  shift

  local script="$repo_dir/packages/$package_name/verify.sh"
  local fingerprints="$*"

  awk -v fingerprints="$fingerprints" '
    /^key_fingerprints=\($/ {
      print
      count = split(fingerprints, list, " ")
      for (i = 1; i <= count; i++) print "  '\''" list[i] "'\''"
      skip = 1
      next
    }
    skip && /^\)$/ { skip = 0 }
    !skip { print }
  ' "$script" > "$script.new"
  mv "$script.new" "$script"
  chmod +x "$script"
}

set_state() {
  local package_name="$1"
  local published_at="$2"

  mkdir -p "$XDG_CONFIG_HOME/verify-from-gpg"
  echo "last_release_published_at='$published_at'" > "$XDG_CONFIG_HOME/verify-from-gpg/$package_name"
}

state_of() {
  local package_name="$1"

  sed -n "s/^last_release_published_at='\(.*\)'$/\1/p" "$XDG_CONFIG_HOME/verify-from-gpg/$package_name" 2> /dev/null
}

published() {
  cut -d ' ' -f 2 "$FAKE_NAK_LOG" 2> /dev/null | sort | tr '\n' ' ' | sed 's/ $//'
}

leftover_files() {
  local package_name="$1"

  find "$repo_dir/packages/$package_name" -mindepth 1 ! -name verify.sh
}
