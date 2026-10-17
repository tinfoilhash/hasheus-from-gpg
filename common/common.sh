# shellcheck shell=bash
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/verify-from-gpg"
relay='wss://verify-relay.tinfoilhash.com'

# any value but 0 means a dry run, so a value like `DRY_RUN=true` can't publish
# for real.
is_dry_run() {
  [ -n "${DRY_RUN:-}" ] && [ "$DRY_RUN" != 0 ]
}

check_dependencies() {
  local commands=(
    'curl'
    'file'
    'gh'
    'gpg'
    'hq'
    'jaq'
    'nak'
    'shasum'
    'xmllint'
  )

  local command
  for command in "${commands[@]}"; do
    if ! command -v "$command" &> /dev/null; then
      echo "$command not found, exiting"
      exit 1
    fi
  done

  if is_dry_run; then
    echo '--- dry run: nothing will be published or recorded'
  fi

  # a dry run only reads from the relay, so it can take the npub instead of the
  # nsec. the nsec wins when both are set, so a dry run checks the same key a
  # real run would publish with.
  local key_variable='$NSEC'

  if [ -n "${NSEC:-}" ]; then
    npub_hex=$(nak key public "$NSEC" < /dev/null 2> /dev/null)
  elif is_dry_run && [ -n "${NPUB:-}" ]; then
    key_variable='$NPUB'
    npub_hex=$(nak decode "$NPUB" < /dev/null 2> /dev/null)
  else
    echo '$NSEC not set, exiting'
    exit 1
  fi

  # nak exits 0 for an invalid key, so check its output instead.
  if [[ ! "$npub_hex" =~ ^[0-9a-f]{64}$ ]]; then
    echo "$key_variable is invalid, exiting"
    exit 1
  fi
}

check_gpg_keys() {
  local key_fingerprints=("$@")

  echo '----- checking for gpg keys'

  local key_fingerprints_found=false

  local key_fingerprint
  for key_fingerprint in "${key_fingerprints[@]}"; do
    if gpg --list-keys "$key_fingerprint"; then
      key_fingerprints_found=true
    fi
  done

  if [ "$key_fingerprints_found" = false ]; then
    echo 'did not find at least one key, exiting'
    exit 1
  fi
}

# release dates come from remote data (coldcard's from scraped filenames), so
# allow only timestamp characters.
published_at_pattern='[0-9TZ:+-]+'

is_valid_published_at() {
  local published_at="$1"

  [[ "$published_at" =~ ^${published_at_pattern}$ ]]
}

# sets `last_release_published_at` and `limit` for the package scripts.
# shellcheck disable=SC2034
source_state() {
  local package_name="$1"

  local state_file="$config_dir/$package_name"

  if [ ! -f "$state_file" ]; then
    mkdir -p "$config_dir"
    last_release_published_at='1970-01-01T00:00:00Z'
    limit=3
    return
  fi

  # parse instead of sourcing so the file's contents are never run as code.
  local state_pattern="^last_release_published_at='(${published_at_pattern})'\$"

  if [[ ! "$(< "$state_file")" =~ $state_pattern ]]; then
    echo "invalid state in $state_file" \
      '(delete it to check the last 3 releases again), exiting'
    exit 1
  fi

  last_release_published_at="${BASH_REMATCH[1]}"
  limit=30
}

verify_gpg_signature() {
  local signature_filename="$1"
  local data_filename="$2"
  shift 2
  local key_fingerprints=("$@")

  local gpg_verify_args=("$signature_filename")

  if [ -n "$data_filename" ]; then
    gpg_verify_args+=("$data_filename")
  fi

  # gpg's exit status accepts any key in the keyring and fails if any one of
  # several signatures can't be checked, so require a valid signature from an
  # allowlisted key instead.
  local status
  status=$(gpg --status-fd 1 --verify "${gpg_verify_args[@]}")

  # each signature's status lines start with NEWSIG. a bad signature has no
  # VALIDSIG line, so it's ignored: it can't vouch for the data, but it doesn't
  # undo a good one (core lightning's manifests can have both, from signers who
  # signed an earlier version). gpg reports a signature from a revoked or
  # expired key as valid too, so skip revoked keys here and check expiry below.
  local valid_signatures
  valid_signatures=$(awk '
    $2 == "NEWSIG" { is_revoked = 0 }
    $2 == "REVKEYSIG" { is_revoked = 1 }
    $2 == "VALIDSIG" && !is_revoked { print $3, $NF, $5 }
  ' <<< "$status")

  local signing_fingerprint primary_fingerprint signed_at
  while read -r signing_fingerprint primary_fingerprint signed_at; do
    # fingerprints are listed by signing subkey or primary key, so match either.
    if printf '%s\n' "${key_fingerprints[@]}" \
      | grep -Fxqi -e "$signing_fingerprint" -e "$primary_fingerprint" \
      && was_key_unexpired_at "$signing_fingerprint" "$signed_at"; then
      return 0
    fi
  done <<< "$valid_signatures"

  return 1
}

# whether a signing key and its primary key hadn't expired yet at the given
# time. a signature made before a key expired still counts, so older releases
# keep verifying.
was_key_unexpired_at() {
  local fingerprint="$1"
  local time="$2"

  gpg --with-colons --fixed-list-mode --list-keys "$fingerprint" 2> /dev/null \
    | awk -F: -v fingerprint="$fingerprint" -v time="$time" '
      function is_unexpired(expires_at) {
        return expires_at == "" || time + 0 < expires_at + 0
      }
      $1 == "pub" || $1 == "sub" { expires_at = $7; is_primary = $1 == "pub" }
      $1 == "fpr" && is_primary {
        primary_expires_at = expires_at
        is_primary = 0
      }
      $1 == "fpr" && $10 == fingerprint { key_expires_at = expires_at }
      END {
        exit !(is_unexpired(primary_expires_at) && is_unexpired(key_expires_at))
      }
    '
}

is_published_to_verify() {
  local hash="$1"

  # about 1 in 20 queries fails to reach the relay. treating that as "not
  # published" would publish a duplicate, so retry, then stop the run.
  local attempt
  for attempt in 1 2 3; do
    local output

    if output=$(nak req -q -k 1063 -a "$npub_hex" -t x="$hash" "$relay" \
      < /dev/null 2>&1); then
      grep -v "filter does not match" <<< "$output" | grep -Fq "$hash"
      return
    fi

    echo "relay query failed (attempt $attempt of 3)"
    sleep "$attempt"
  done

  echo 'relay query failed, exiting'
  exit 1
}

publish_to_verify() {
  local filename="$1"
  local hash="$2"
  local url="$3"
  local content_type="$4"
  local size="$5"

  if is_dry_run; then
    echo "dry run: would publish $filename"
    return
  fi

  nak event -k 1063 -c "$filename" \
    -t x="$hash" -t url="$url" -t m="$content_type" -t size="$size" \
    --sec "$NSEC" "$relay" < /dev/null
}

# prints the file name from a manifest line, without shasum's `*` (binary mode)
# or a leading `./`.
manifest_filename() {
  local shasum_line="$1"

  local hash filename
  read -r hash filename <<< "$shasum_line"
  filename="${filename#\*}"

  echo "${filename#./}"
}

# publishes the file on a verified manifest line: skips it if it's already
# published, otherwise downloads it, checks it against the line, and publishes
# it. the content type and size default to the downloaded file's.
publish_file() {
  local shasum_line="$1"
  local url="$2"
  local content_type="${3:-}"
  local size="${4:-}"

  local hash filename_shasum
  read -r hash filename_shasum <<< "$shasum_line"

  local filename
  filename=$(manifest_filename "$shasum_line")

  # shasum only accepts two spaces (or " *" for binary mode) between the hash
  # and the name, and some manifests, like amber's, use one.
  local check_line="$hash  $filename_shasum"
  if [[ "$filename_shasum" == \** ]]; then
    check_line="$hash $filename_shasum"
  fi

  if is_published_to_verify "$hash"; then
    echo 'file already verified, skipping'
    return
  fi

  echo '------- downloading file'

  download_file "$url" "$filename" || exit 1

  if [ -z "$content_type" ]; then
    content_type=$(file --mime-type -b "$filename")
  fi

  if [ -z "$size" ]; then
    size=$(wc -c < "$filename" | tr -d ' ')
  fi

  echo "filename: $filename"
  echo "hash: $hash"
  echo "url: $url"
  echo "content type: $content_type"
  echo "size: $size"

  if shasum --check --status <<< "$check_line"; then
    echo 'verified: yes'
  else
    echo 'verified: no'
    # a failed download can also cause this, so exit without recording the
    # release and try again on the next run.
    echo 'file not verified, exiting'
    exit 1
  fi

  echo '------- publishing event'

  publish_to_verify "$filename" "$hash" "$url" "$content_type" "$size" || exit 1
}

download_file() {
  local url="$1"
  local filename="${2:-${url##*/}}"

  # release files can be several gb, so abort stalled transfers instead of
  # capping the total time.
  curl -fL --connect-timeout 30 --speed-limit 1024 --speed-time 60 \
    -o "$filename" "$url"
}

# `package_dir` is set by each package script.
# shellcheck disable=SC2154
start_release() {
  local published_at="$1"

  # check the date before anything is published, since it's recorded only after.
  if ! is_valid_published_at "$published_at"; then
    echo "invalid release date: $published_at, exiting"
    exit 1
  fi

  # start every attempt from an empty directory so a partial download from an
  # interrupted run is never reused.
  release_dir=$(mktemp -d "$package_dir/release.XXXXXX") || exit 1
  trap 'rm -rf "$release_dir"' EXIT

  cd "$release_dir" || exit 1
}

complete_release() {
  local package_name="$1"
  local published_at="$2"

  local state_file="$config_dir/$package_name"

  cd "$package_dir" || exit 1
  rm -r "$release_dir"

  if is_dry_run; then
    echo "dry run: would record $published_at"
    return
  fi

  cat > "$state_file" << EOF
last_release_published_at='$published_at'
EOF
}
