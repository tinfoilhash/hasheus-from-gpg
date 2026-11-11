#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup_file() {
  setup_keyring
}

teardown_file() {
  teardown_keyring
}

write_openwrt_index() {
  local directory="$1"
  shift
  mkdir -p "$directory"
  echo '<html><table><tr><th>name</th><th>date</th></tr>' \
    > "$directory/index.html"
  local filename
  for filename in "$@"; do
    echo "<tr><td><a href=\"$filename\">$filename</a></td>" \
      '<td>Tue Oct  6 00:16:00 2026</td></tr>' >> "$directory/index.html"
  done
  echo '</table></html>' >> "$directory/index.html"
}

prepare_openwrt_release() {
  create_repo openwrt
  set_key_fingerprints openwrt "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  local root="$FAKE_CURL_ROOT/downloads.openwrt.org/releases"
  write_openwrt_index "$root" 25.12.6/
  write_openwrt_index "$root/25.12.6/targets" x86/ rockchip/
  write_openwrt_index "$root/25.12.6/targets/x86" 64/
  write_openwrt_index "$root/25.12.6/targets/rockchip" armv8/
  local target
  for target in x86/64 rockchip/armv8; do
    local dir="$root/25.12.6/targets/$target"
    mkdir -p "$dir"
    cd "$dir" || exit 1
    local files=(firmware.bin)
    [ "$target" = x86/64 ] && files=(firmware.img.gz firmware.vmdk)
    local filename
    for filename in "${files[@]}"; do
      echo "$target $filename" > "$filename"
    done
    shasum -a 256 "${files[@]}" > sha256sums
    local signer=signer
    if [ "$target" = rockchip/armv8 ]; then
      signer="${SECOND_TARGET_SIGNER:-signer}"
    fi
    sign_detached "$signer" sha256sums sha256sums.asc
    write_openwrt_index "$dir" "${files[@]}" sha256sums sha256sums.asc
  done
}

@test 'openwrt verifies all targets, architectures and image formats' {
  prepare_openwrt_release
  run "$repo_dir/packages/openwrt/verify.sh"
  [ "$status" -eq 0 ]
  published_is 'firmware.bin firmware.img.gz firmware.vmdk'
  [ "$(state_of openwrt)" = '2026-10-06T00:16:00Z' ]
  [ -z "$(leftover_files openwrt)" ]
}

@test 'openwrt does not record a release when a later target is unverified' {
  SECOND_TARGET_SIGNER=stranger prepare_openwrt_release
  run "$repo_dir/packages/openwrt/verify.sh"
  [ "$status" -eq 1 ]
  published_is 'firmware.img.gz firmware.vmdk'
  [ -z "$(state_of openwrt)" ]
}
