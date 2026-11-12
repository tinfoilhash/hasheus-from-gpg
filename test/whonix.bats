#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup_file() {
  setup_keyring
}

teardown_file() {
  teardown_keyring
}

whonix_index() {
  local directory="$1"
  shift
  mkdir -p "$directory"
  echo '<table><tr><th>name</th></tr>' > "$directory/index.html"
  local name
  for name in "$@"; do
    echo "<tr><td><a href=\"$name\">file</a></td>" \
      '<td>2026-Oct-06 00:16</td></tr>' >> "$directory/index.html"
  done
  echo '</table>' >> "$directory/index.html"
}

setup() {
  create_repo whonix
  set_key_fingerprints whonix "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  root="$FAKE_CURL_ROOT/www.whonix.org/download"
  whonix_index "$root" developer-meta-files/ ova/ libvirt/ windows/ iso/
  whonix_index "$root/iso"
  local category arch
  for category in ova libvirt windows; do
    local version=18.2.4.3
    [ "$category" = windows ] && version=18.1.4.2
    whonix_index "$root/$category" "$version/"
    whonix_index "$root/$category/$version" amd64/ arm64/
    for arch in amd64 arm64; do
      local dir="$root/$category/$version/$arch"
      local filename="Whonix-$version.$category"
      whonix_index "$dir" "$filename" "$filename.asc"
      echo "$category $arch" > "$dir/$filename"
      sign_detached signer "$dir/$filename" "$dir/$filename.asc"
    done
  done
}

@test 'whonix checks all categories and repeated architecture filenames' {
  run "$repo_dir/packages/whonix/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$FAKE_HASHEUS_LOG" | tr -d ' ')" = 6 ]
  local category
  for category in ova libvirt windows; do
    [ "$(state_of "whonix_$category")" = '2026-10-06T00:16:00Z' ]
  done
  [ -z "$(state_of whonix_iso)" ]
}

@test 'whonix does not record a category with an unlisted image signer' {
  local dir="$root/libvirt/18.2.4.3/arm64"
  sign_detached stranger "$dir/Whonix-18.2.4.3.libvirt" \
    "$dir/Whonix-18.2.4.3.libvirt.asc"
  run "$repo_dir/packages/whonix/verify.sh"
  [ "$status" -eq 1 ]
  [ "$(state_of whonix_ova)" = '2026-10-06T00:16:00Z' ]
  [ -z "$(state_of whonix_libvirt)" ]
  [ -z "$(state_of whonix_windows)" ]
}
