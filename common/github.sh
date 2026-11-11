# shellcheck shell=bash
source "${BASH_SOURCE%/*}/releases.sh"

github_releases() {
  gh release list --repo "$1" --exclude-drafts --limit "$limit" \
    --json tagName,publishedAt
}

github_release_assets() {
  gh release view "$2" --repo "$1" --json assets
}

list_releases() {
  github_releases "$@"
}

list_release_assets() {
  github_release_assets "$@"
}

verify_from_github() {
  verify_with_manifest "$@"
}

verify_signed_files_from_github() {
  verify_with_signed_files "$@"
}

verify_signed_checksums_from_github() {
  verify_with_signed_checksums "$@"
}
