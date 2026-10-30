# shellcheck shell=bash
source "${BASH_SOURCE%/*}/common.sh"

resolve_filename_pattern() {
  local pattern="$1"
  local name="$2"

  if [ "$(type -t "$pattern")" = 'function' ]; then
    "$pattern" "$name"
  else
    echo "${pattern//\{\{NAME\}\}/$name}"
  fi
}

matching_asset_names() {
  local pattern="$1"
  local asset_names="$2"

  local asset_name
  while IFS= read -r asset_name; do
    # unquoted so the pattern matches as a glob.
    # shellcheck disable=SC2053
    if [[ "$asset_name" == $pattern ]]; then
      echo "$asset_name"
    fi
  done <<< "$asset_names"
}

download_asset() {
  local release_assets="$1"
  local filename="$2"

  local url
  url=$(jaq -r --arg filename "$filename" \
    '.assets[] | select(.name == $filename) | .url' <<< "$release_assets") \
    || return 1

  download_file "$url" "$filename"
}

# prints "<url>,<content type>,<size>" for the release asset with the file
# name, or nothing if there isn't one.
asset_details() {
  local release_assets="$1"
  local filename="$2"

  jaq -r --arg filename "$filename" '
    .assets[]
    | select(.name == $filename)
    | "\(.url),\(.contentType),\(.size)"
  ' <<< "$release_assets"
}

verify_from_github() {
  local package_name="$1"
  local repo="$2"
  local shasum_filename_pattern="$3"
  local shasum_signature_filename_pattern="$4"
  shift 4
  local key_fingerprints=("$@")

  source_state "$package_name"

  check_gpg_keys "${key_fingerprints[@]}"

  verify_new_releases "$package_name" "$repo" verify_manifest_release \
    "$shasum_filename_pattern" "$shasum_signature_filename_pattern" \
    "${key_fingerprints[@]}"
}

# for projects that sign each file instead of a manifest, like trezor suite's
# <file>.asc. only files with a signature are published.
verify_signed_files_from_github() {
  local package_name="$1"
  local repo="$2"
  local signature_suffix="$3"
  shift 3
  local key_fingerprints=("$@")

  source_state "$package_name"

  check_gpg_keys "${key_fingerprints[@]}"

  verify_new_releases "$package_name" "$repo" verify_signed_files_release \
    "$signature_suffix" "${key_fingerprints[@]}"
}

# calls the given function for each release published since the last run,
# oldest first, with the release's name, assets (as gh's json), and asset
# names, plus any further arguments. the release is recorded once it returns.
verify_new_releases() {
  local package_name="$1"
  local repo="$2"
  local verify_release="$3"
  shift 3

  echo '----- getting list of releases'

  local releases
  releases=$(gh release list --repo "$repo" --exclude-drafts --limit "$limit" \
    --json tagName,publishedAt) || exit 1

  echo '----- checking for new releases'

  local new_releases
  new_releases=$(jaq -r --arg since "$last_release_published_at" '
    map(select(.publishedAt > $since))
    | reverse
    | .[]
    | "\(.tagName),\(.publishedAt)"
  ' <<< "$releases") || exit 1

  local new_releases_count
  new_releases_count=$(printf '%s' "$new_releases" | grep -c '^')

  echo "new releases found: $new_releases_count"

  if [ "$new_releases_count" -eq 0 ]; then
    return
  fi

  while IFS=',' read -r name published_at; do
    echo "- $name ($published_at)"
  done <<< "$new_releases"

  # read from a separate file descriptor so the loop runs in this shell (letting
  # `exit` stop the script) and nothing inside it can consume the list.
  while IFS=',' read -r name published_at <&3; do
    echo "----- new release: $name ($published_at)"

    echo '------- getting list of assets'

    local release_assets
    release_assets=$(gh release view "$name" --repo "$repo" --json assets) \
      || exit 1

    local asset_names
    asset_names=$(jaq -r '.assets[].name' <<< "$release_assets") || exit 1
    asset_names=$(sort <<< "$asset_names")

    start_release "$published_at"

    # the function exits on any failure, but a return that isn't 0 still stops
    # the release from being recorded.
    "$verify_release" "$name" "$release_assets" "$asset_names" "$@" || exit 1

    complete_release "$package_name" "$published_at"
  done 3<<< "$new_releases"
}

verify_manifest_release() {
  local name="$1"
  local release_assets="$2"
  local asset_names="$3"
  local shasum_filename_pattern="$4"
  local shasum_signature_filename_pattern="$5"
  shift 5
  local key_fingerprints=("$@")

  echo '------- downloading hashes and gpg signatures'

  local shasum_pattern shasum_signature_pattern
  shasum_pattern=$(resolve_filename_pattern "$shasum_filename_pattern" "$name")
  shasum_signature_pattern=$(
    resolve_filename_pattern "$shasum_signature_filename_pattern" "$name"
  )

  local shasum_filename
  shasum_filename=$(
    matching_asset_names "$shasum_pattern" "$asset_names" | head -n 1
  )

  if [ -z "$shasum_filename" ]; then
    echo 'hashes file does not exist, skipping'
    return
  fi

  # one match per signer, like lnd's manifest-<signer>-<tag>.sig.
  local shasum_signature_filenames=()
  local shasum_signature_filename
  while IFS= read -r shasum_signature_filename; do
    shasum_signature_filenames+=("$shasum_signature_filename")
  done < <(matching_asset_names "$shasum_signature_pattern" "$asset_names")

  if [ "${#shasum_signature_filenames[@]}" -eq 0 ]; then
    echo 'gpg signatures file does not exist, skipping'
    return
  fi

  local is_shasum_signature_detached=true
  local shasum_signed_filename="$shasum_filename"

  if [ "$shasum_filename" = "${shasum_signature_filenames[0]}" ]; then
    is_shasum_signature_detached=false
    shasum_signed_filename=''
  else
    download_asset "$release_assets" "$shasum_filename" || exit 1
  fi

  for shasum_signature_filename in "${shasum_signature_filenames[@]}"; do
    download_asset "$release_assets" "$shasum_signature_filename" || exit 1
  done

  echo '------- verifying gpg signatures'

  local is_shasum_signature_verified=false

  for shasum_signature_filename in "${shasum_signature_filenames[@]}"; do
    if verify_gpg_signature "$shasum_signature_filename" \
      "$shasum_signed_filename" "${key_fingerprints[@]}"; then
      is_shasum_signature_verified=true
      break
    fi
  done

  # exit without recording the release, so it's tried again once the signer's
  # key is listed or the signature is fixed.
  if [ "$is_shasum_signature_verified" = false ]; then
    echo 'gpg signatures verification failed, exiting'
    exit 1
  fi

  local shasum_manifest

  if [ "$is_shasum_signature_detached" = true ]; then
    shasum_manifest=$(< "$shasum_filename")
  else
    shasum_manifest=$(gpg --decrypt "$shasum_signature_filename" 2> /dev/null)
  fi

  # download each file only after the signature verifies and only if it isn't
  # published yet, since a release can be several gb.
  local shasum_line
  while IFS= read -r shasum_line <&4; do
    local filename
    filename=$(manifest_filename "$shasum_line")

    echo "------- processing file: $filename"

    # some manifests, like alby hub's, list themselves, hashed before they were
    # written, so that entry can never match.
    if [ "$filename" = "$shasum_filename" ]; then
      echo 'file is the manifest itself, skipping'
      continue
    fi

    local release_asset
    release_asset=$(asset_details "$release_assets" "$filename") || exit 1

    # some manifests, like mostro's, list each file under the directory it was
    # built in.
    if [ -z "$release_asset" ] && [[ "$filename" == */* ]]; then
      local hash
      read -r hash _ <<< "$shasum_line"
      filename="${filename##*/}"
      shasum_line="$hash  $filename"
      release_asset=$(asset_details "$release_assets" "$filename") || exit 1
    fi

    # manifests can also list files that aren't release assets, like the
    # binaries inside lnd's archives.
    if [ -z "$release_asset" ]; then
      echo 'file is not a release asset, skipping'
      continue
    fi

    local url content_type size
    IFS=',' read -r url content_type size <<< "$release_asset"

    publish_file "$shasum_line" "$url" "$content_type" "$size"
  done 4<<< "$shasum_manifest"
}

verify_signed_files_release() {
  local name="$1"
  local release_assets="$2"
  local asset_names="$3"
  local signature_suffix="$4"
  shift 4
  local key_fingerprints=("$@")

  local signed_asset_names
  signed_asset_names=$(signed_filenames "$asset_names" "$signature_suffix")

  if [ -z "$signed_asset_names" ]; then
    echo 'signed files do not exist, skipping'
    return
  fi

  local filename
  while IFS= read -r filename <&4; do
    echo "------- processing file: $filename"

    local release_asset
    release_asset=$(jaq -r --arg filename "$filename" \
      --arg signature_filename "$filename$signature_suffix" '
      (
        .assets[] | select(.name == $signature_filename) | .url
      ) as $signature_url
      | .assets[]
      | select(.name == $filename)
      | "\(.url),\($signature_url),\(.contentType),\(.size),\(.digest // "")"
    ' <<< "$release_assets") || exit 1

    local url signature_url content_type size digest
    IFS=',' read -r url signature_url content_type size digest \
      <<< "$release_asset"

    publish_signed_file "$filename" "$url" "$signature_url" "$content_type" \
      "$size" "$digest" "${key_fingerprints[@]}"
  done 4<<< "$signed_asset_names"
}
