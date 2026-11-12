#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying borgbackup'

package_name='borgbackup'
repo='borgbackup/borg'
key_fingerprints=(
  '6D5BEF9ADD2075805747B70F9F88FB52FAF7B393' # https://keys.openpgp.org/vks/v1/by-fingerprint/6D5BEF9ADD2075805747B70F9F88FB52FAF7B393
)
signature_suffix='.asc'

list_releases() {
  gh release list --repo "$1" --exclude-drafts --exclude-pre-releases \
    --limit "$limit" --json tagName,publishedAt
}

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
