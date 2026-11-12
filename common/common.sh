# shellcheck shell=bash
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hasheus-from-gpg"

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
    'hasheus'
    'hq'
    'jaq'
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

  # hasheus checks the keys when it first uses them. the public key is the one
  # already published files are looked up by, and a dry run only reads, so it
  # doesn't need the secret key.
  if [ -z "${HASHEUS_PUBLIC_KEY:-}" ]; then
    echo '$HASHEUS_PUBLIC_KEY not set, exiting'
    exit 1
  fi

  if ! is_dry_run && [ -z "${HASHEUS_SECRET_KEY:-}" ]; then
    echo '$HASHEUS_SECRET_KEY not set, exiting'
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

# hasheus prints an error as json, with a code to branch on.
hasheus_error_code() {
  local output="$1"

  jaq -r '.error.code // empty' <<< "$output" 2> /dev/null
}

print_hasheus_error() {
  local output="$1"

  local message
  message=$(jaq -r '.error.message // empty' <<< "$output" 2> /dev/null)
  echo "hasheus failed: ${message:-no error printed}, exiting"
}

# a relay can be unreachable, or reject an event for a while (like when rate
# limiting), so those are worth retrying. anything else, like an invalid key,
# won't fix itself.
is_transient_hasheus_error() {
  local output="$1"

  case "$(hasheus_error_code "$output")" in
    file_relays_unreachable | user_relays_unreachable | publish_rejected)
      return 0
      ;;
    *) return 1 ;;
  esac
}

is_published_to_verify() {
  local hash="$1"

  # about 1 in 20 queries fails to reach the relay. treating that as "not
  # published" would publish a duplicate, so retry, then stop the run.
  local attempt
  for attempt in 1 2 3; do
    local output

    if output=$(hasheus verify "$hash" --json < /dev/null); then
      [ "$(jaq -r '.verification.status' <<< "$output")" = verified_by_you ]
      return
    fi

    if ! is_transient_hasheus_error "$output"; then
      print_hasheus_error "$output"
      exit 1
    fi

    echo "relay query failed (attempt $attempt of 3)"
    sleep "$attempt"
  done

  echo 'relay query failed, exiting'
  exit 1
}

publish_to_verify() {
  local hash="$1"
  local filename="$2"
  local url="$3"
  local content_type="$4"

  if is_dry_run; then
    echo "dry run: would publish $filename"
    return
  fi

  # a publish can fail to reach the relay too, so retry. hasheus checks that it
  # didn't land anyway before each one, so the event isn't published twice. it
  # also fails after publishing if it can't show the result, which a retry
  # catches the same way, and so does a last check after the last attempt.
  local attempt
  for attempt in 1 2 3; do
    local output

    # the `=` and `--` keep a file name that starts with `-` from reading as
    # an option.
    if output=$(hasheus publish --url "$url" --description="$filename" \
      --mime-type "$content_type" --yes --json -- "$filename" \
      < /dev/null); then
      echo 'published'
      return
    fi

    if [ "$(hasheus_error_code "$output")" = already_verified ]; then
      echo 'event was published after all'
      return
    fi

    if ! is_transient_hasheus_error "$output"; then
      print_hasheus_error "$output"
      return 1
    fi

    echo "publish failed (attempt $attempt of 3)"
    sleep "$attempt"
  done

  if is_published_to_verify "$hash"; then
    echo 'event was published after all'
    return
  fi

  echo 'publish failed, exiting'
  return 1
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

# github reports some assets' content type as just "raw", which hasheus
# rejects, since a mime type needs a type and subtype.
is_mime_type() {
  [[ "$1" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]
}

# publishes the file on a verified manifest line: skips it if it's already
# published, otherwise downloads it, checks it against the line, and publishes
# it. the content type defaults to the downloaded file's, and so does one that
# isn't a mime type.
publish_file() {
  local shasum_line="$1"
  local url="$2"
  local content_type="${3:-}"
  local algorithm="${4:-256}"

  if [ "$algorithm" != 256 ] && [ "$algorithm" != 512 ]; then
    echo 'unsupported manifest hash algorithm, exiting'
    exit 1
  fi

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

  if [ "$algorithm" = 256 ] && is_published_to_verify "$hash"; then
    echo 'file already verified, skipping'
    return
  fi

  echo '------- downloading file'

  download_file "$url" "$filename" || exit 1

  if ! is_mime_type "$content_type"; then
    content_type=$(file --mime-type -b "$filename")
  fi

  echo "filename: $filename"
  echo "hash: $hash"
  echo "url: $url"
  echo "content type: $content_type"

  if shasum -a "$algorithm" --check --status <<< "$check_line"; then
    echo 'verified: yes'
  else
    echo 'verified: no'
    skip_unverified_file "$filename"
    return
  fi

  if [ "$algorithm" != 256 ]; then
    hash=$(shasum -a 256 -- "$filename") || exit 1
    hash="${hash%% *}"
    if is_published_to_verify "$hash"; then
      echo 'file already verified, skipping'
      return
    fi
  fi

  echo '------- publishing event'

  publish_to_verify "$hash" "$filename" "$url" "$content_type" || exit 1
}

# prints each file name that has a signature among the names, as
# <name><suffix>. files without one, like electron's update metadata, are left
# out, and so are signatures without a file, like the keys bisq attaches as
# <id>.asc.
signed_filenames() {
  local filenames="$1"
  local signature_suffix="$2"

  local filename
  while IFS= read -r filename; do
    if grep -Fxq -- "$filename$signature_suffix" <<< "$filenames"; then
      echo "$filename"
    fi
  done <<< "$filenames"
}

# like `publish_file`, but checks the file against its own signature. a known
# digest (like github's) is used only to skip a file that's already published
# without downloading it: what's published is the downloaded file's hash, once
# its signature verifies. the content type defaults to the downloaded
# file's, and so does one that isn't a mime type.
publish_signed_file() {
  local filename="$1"
  local url="$2"
  local signature_url="$3"
  local content_type="${4:-}"
  local digest="${5:-}"
  shift 5
  local key_fingerprints=("$@")

  local digest_hash="${digest#sha256:}"
  if [[ ! "$digest_hash" =~ ^[0-9a-f]{64}$ ]]; then
    digest_hash=''
  fi

  if [ -n "$digest_hash" ] && is_published_to_verify "$digest_hash"; then
    echo 'file already verified, skipping'
    return
  fi

  echo '------- downloading file and gpg signature'

  local signature_filename="${signature_url##*/}"

  download_file "$signature_url" "$signature_filename" || exit 1
  download_file "$url" "$filename" || exit 1

  publish_downloaded_signed_file "$filename" "$url" "$signature_filename" \
    "$content_type" "$digest_hash" "${key_fingerprints[@]}"
}

publish_downloaded_signed_file() {
  local filename="$1"
  local url="$2"
  local signature_filename="$3"
  local content_type="$4"
  local digest_hash="$5"
  shift 5
  local key_fingerprints=("$@")

  local hash
  hash=$(shasum -a 256 -- "$filename") || exit 1
  hash="${hash%% *}"

  if [ "$hash" != "$digest_hash" ] && is_published_to_verify "$hash"; then
    echo 'file already verified, skipping'
    return
  fi

  if ! is_mime_type "$content_type"; then
    content_type=$(file --mime-type -b "$filename")
  fi

  echo "filename: $filename"
  echo "hash: $hash"
  echo "url: $url"
  echo "content type: $content_type"

  if verify_gpg_signature "$signature_filename" "$filename" \
    "${key_fingerprints[@]}"; then
    echo 'verified: yes'
  else
    echo 'verified: no'

    # anything but a bad signature, like one from a key that isn't listed yet,
    # can be fixed on our side, so exit without recording the release and try
    # again on the next run.
    if ! has_bad_signature "$signature_filename" "$filename"; then
      echo 'file not verified, exiting'
      exit 1
    fi

    skip_unverified_file "$filename"
    return
  fi

  echo '------- publishing event'

  publish_to_verify "$hash" "$filename" "$url" "$content_type" || exit 1
}

# whether gpg finds a signature that doesn't match the data, so the file isn't
# what was signed and listing or importing a key can't fix it.
has_bad_signature() {
  local signature_filename="$1"
  local data_filename="$2"

  gpg --status-fd 1 --verify "$signature_filename" "$data_filename" \
    2> /dev/null | grep -q '^\[GNUPG:\] BADSIG '
}

publish_from_signed_checksum() {
  local filename="$1"
  local url="$2"
  local checksum_url="$3"
  local signature_url="$4"
  shift 4
  local key_fingerprints=("$@")

  if [[ ! "$filename" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
    echo 'invalid checksum filename, exiting'
    exit 1
  fi

  local checksum_filename="$filename.sha256"
  local signature_filename="$checksum_filename.sig"
  download_file "$checksum_url" "$checksum_filename" || exit 1
  download_file "$signature_url" "$signature_filename" || exit 1

  if ! verify_gpg_signature "$signature_filename" "$checksum_filename" \
    "${key_fingerprints[@]}"; then
    if has_bad_signature "$signature_filename" "$checksum_filename"; then
      skip_unverified_file "$filename"
      return
    fi
    echo 'checksum signature verification failed, exiting'
    exit 1
  fi

  local hash
  hash=$(< "$checksum_filename")
  hash="${hash%$'\r'}"
  if [[ ! "$hash" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo 'invalid signed sha256 checksum, exiting'
    exit 1
  fi

  publish_file "$hash  $filename" "$url"
}

# a file that fails its hash check or has a bad signature isn't what the
# project published or signed, so it's theirs to fix (a failed download fails
# before the check). it's never published, but it doesn't stop the run, so one
# bad file doesn't block the release's other files and later releases.
# `complete_release` still exits 1 so it's reported.
skip_unverified_file() {
  local filename="$1"

  echo 'file not verified, skipping'
  unverified_filenames+=("$filename")
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

  unverified_filenames=()

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
  else
    cat > "$state_file" << EOF
last_release_published_at='$published_at'
EOF
  fi

  # the release is recorded so the next run moves past it, but stop this run so
  # the skipped files are reported.
  if [ "${#unverified_filenames[@]}" -gt 0 ]; then
    echo "skipped files that failed verification" \
      "(${unverified_filenames[*]}), exiting"
    exit 1
  fi
}
