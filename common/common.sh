config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/verify-from-gpg"
relay='wss://verify-relay.tinfoilhash.com'

npub_hex=$(nak key public "$NSEC")

check_dependencies() {
  local commands=(
    'gh'
    'gpg'
    'hq'
    'jaq'
    'nak'
  )

  local command
  for command in "${commands[@]}"; do
    if ! type "$command" &> /dev/null; then
      echo "$command not found, exiting"
      exit 1
    fi
  done

  if [ ! -n "${NSEC+set}" ]; then
    echo '$NSEC not set, exiting'
    exit 1
  fi
}

is_valid_published_at() {
  local published_at="$1"

  # Release dates come from remote data (coldcard's from scraped filenames), so allow only timestamp characters.
  [[ "$published_at" =~ ^[0-9TZ:+-]+$ ]]
}

source_state() {
  local package_name="$1"

  local state_file="$config_dir/$package_name"

  if [ ! -f "$state_file" ]; then
    mkdir -p "$config_dir"
    last_release_published_at='1970-01-01T00:00:00Z'
    limit=3
    return
  fi

  # Parse instead of sourcing so the file's contents are never run as code.
  last_release_published_at=$(sed -n "s/^last_release_published_at='\(.*\)'\$/\1/p" "$state_file")
  limit=30

  if ! is_valid_published_at "$last_release_published_at"; then
    echo "invalid state in $state_file, exiting"
    exit 1
  fi
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

  # gpg's exit status accepts any key in the keyring and fails if any one of several signatures can't be checked,
  # so require a valid signature from an allowlisted key instead.
  local status=$(gpg --status-fd 1 --verify "${gpg_verify_args[@]}")

  if echo "$status" | grep -q '^\[GNUPG:\] BADSIG '; then
    return 1
  fi

  # Fingerprints are allowlisted by signing subkey or primary key, so match either.
  local signer_fingerprints=$(echo "$status" | awk '$2 == "VALIDSIG" { print $3; print $NF }')

  local key_fingerprint
  for key_fingerprint in "${key_fingerprints[@]}"; do
    if echo "$signer_fingerprints" | grep -Fxqi "$key_fingerprint"; then
      return 0
    fi
  done

  return 1
}

is_published_to_verify() {
  local hash="$1"

  nak req -q -k 1063 -a "$npub_hex" -t x="$hash" "$relay" < /dev/null 2>&1 \
  | grep -v "filter does not match" \
  | grep -Fq "$hash"
}

publish_to_verify() {
  local filename="$1"
  local hash="$2"
  local url="$3"
  local content_type="$4"
  local size="$5"

  nak event -k 1063 -c "$filename" -t x="$hash" -t url="$url" -t m="$content_type" -t size="$size" --sec "$NSEC" "$relay" < /dev/null
}

download_file() {
  local url="$1"

  # Release files can be several GB, so abort stalled transfers instead of capping the total time.
  curl -fL --connect-timeout 30 --speed-limit 1024 --speed-time 60 -O "$url"
}

start_release() {
  # Start every attempt from an empty directory so a partial download from an interrupted run is never reused.
  release_dir=$(mktemp -d "$package_dir/release.XXXXXX") || exit 1
  trap 'rm -rf "$release_dir"' EXIT

  cd "$release_dir" || exit 1
}

complete_release() {
  local package_name="$1"
  local published_at="$2"

  local state_file="$config_dir/$package_name"

  if ! is_valid_published_at "$published_at"; then
    echo "invalid release date: $published_at, exiting"
    exit 1
  fi

  cd "$package_dir" || exit 1
  rm -r "$release_dir"

  cat > "$state_file" << EOF
last_release_published_at='$published_at'
EOF
}
