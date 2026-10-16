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

verify_from_github() {
  local package_name="$1"
  local repo="$2"
  local shasum_filename_pattern="$3"
  local shasum_signature_filename_pattern="$4"
  shift 4
  local key_fingerprints=("$@")

  source_state "$package_name"

  check_gpg_keys "${key_fingerprints[@]}"

  echo '----- getting list of releases'

  local releases
  releases=$(gh release list --repo "$repo" --exclude-drafts --limit "$limit" --json tagName,publishedAt) || exit 1

  echo '----- checking for new releases'

  local new_releases=$(jaq -r --arg since "$last_release_published_at" 'map(select(.publishedAt > $since)) | reverse | .[] | "\(.tagName),\(.publishedAt)"' <<< "$releases")
  local new_releases_count=$(printf '%s' "$new_releases" | grep -c '^')

  echo "new releases found: $new_releases_count"

  if [ "$new_releases_count" -eq 0 ]; then
    return
  fi

  while IFS=',' read -r name published_at; do
    echo "- $name ($published_at)"
  done <<< "$new_releases"

  # Read from a separate file descriptor so the loop runs in this shell (letting `exit` stop the script) and nothing
  # inside it can consume the list.
  while IFS=',' read -r name published_at <&3; do
    echo "----- new release: $name ($published_at)"

    echo '------- getting list of assets'

    local release_assets
    release_assets=$(gh release view "$name" --repo "$repo" --json assets) || exit 1

    echo '------- downloading assets'

    start_release

    gh release download "$name" --repo "$repo" || exit 1

    echo '------- verifying gpg signatures'

    # glob expansion, use first match
    local shasum_filenames=( $(resolve_filename_pattern "$shasum_filename_pattern" "$name") )
    local shasum_filename="${shasum_filenames[0]}"

    if [ ! -f "$shasum_filename" ]; then
      echo 'hashes file does not exist, skipping'
      complete_release "$package_name" "$published_at"
      continue
    fi

    # glob expansion, one match per signer
    local shasum_signature_filenames=( $(resolve_filename_pattern "$shasum_signature_filename_pattern" "$name") )

    if [ ! -f "${shasum_signature_filenames[0]}" ]; then
      echo 'gpg signatures file does not exist, skipping'
      complete_release "$package_name" "$published_at"
      continue
    fi

    local is_shasum_signature_detached=true
    local shasum_signed_filename="$shasum_filename"

    if [ "$shasum_filename" = "${shasum_signature_filenames[0]}" ]; then
      is_shasum_signature_detached=false
      shasum_signed_filename=''
    fi

    local is_shasum_signature_verified=false
    local shasum_signature_filename

    for shasum_signature_filename in "${shasum_signature_filenames[@]}"; do
      if verify_gpg_signature "$shasum_signature_filename" "$shasum_signed_filename" "${key_fingerprints[@]}"; then
        is_shasum_signature_verified=true
        break
      fi
    done

    if [ "$is_shasum_signature_verified" = false ]; then
      echo 'gpg signatures verification failed, skipping'
      complete_release "$package_name" "$published_at"
      continue
    fi

    echo '------- verifying hashes'

    local shasum_manifest

    if [ "$is_shasum_signature_detached" = true ]; then
      shasum_manifest=$(<"$shasum_filename")
    else
      shasum_manifest=$(gpg --decrypt "$shasum_signature_filename" 2>/dev/null)
    fi

    local shasum_check=$(shasum --check --ignore-missing <<< "$shasum_manifest")

    while IFS=' ' read -r hash filename_shasum <&4; do
      local filename="${filename_shasum#\*}"
      filename="${filename#./}"

      echo "------- processing file: $filename"

      if [ ! -f "$filename" ]; then
        echo 'file does not exist, skipping'
        continue
      fi

      if is_published_to_verify "$hash"; then
        echo 'file already verified, skipping'
        continue
      fi

      local release_asset=$(jaq -r --arg filename "$filename" '.assets[] | select(.name == $filename) | "\(.url),\(.contentType),\(.size)"' <<< "$release_assets")

      if [ -z "$release_asset" ]; then
        echo 'release asset not found, exiting'
        exit 1
      fi

      IFS=',' read -r url content_type size <<< "$release_asset"

      echo "filename: $filename"
      echo "hash: $hash"
      echo "url: $url"
      echo "content type: $content_type"
      echo "size: $size"

      if grep -Fxq -e "$filename: OK" -e "$filename_shasum: OK" <<< "$shasum_check"; then
        echo 'verified: yes'
      else
        echo 'verified: no'
        echo 'file not verified, skipping'
        continue
      fi

      echo '------- publishing event'

      if ! publish_to_verify "$filename" "$hash" "$url" "$content_type" "$size"; then
        exit 1
      fi
    done 4<<< "$shasum_manifest"

    complete_release "$package_name" "$published_at"
  done 3<<< "$new_releases"
}
