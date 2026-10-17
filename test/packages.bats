#!/usr/bin/env bats

# runs each github package's real script, with its own file name patterns,
# against a release named the way that project names its files. only the key
# fingerprints are swapped for the test keys.

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup_file() {
  setup_keyring
}

teardown_file() {
  teardown_keyring
}

# writes a fake release <tag> with the asset, its hashes in <manifest>, and
# <signature> over them. when the manifest and signature are the same file, it's
# clearsigned. any further arguments are extra assets that aren't hashed.
run_release() {
  local package_name="$1"
  local tag="$2"
  local manifest="$3"
  local signature="$4"
  local asset="$5"
  shift 5

  create_repo "$package_name"
  set_key_fingerprints "$package_name" "$(fingerprint_of signer)"

  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  export FAKE_GH_ROOT="$FAKE_CURL_ROOT/github.example"

  local release_dir="$FAKE_GH_ROOT/$tag"
  mkdir -p "$release_dir"
  cd "$release_dir" || exit 1

  echo "$asset" > "$asset"
  shasum -a 256 "$asset" > "$BATS_TEST_TMPDIR/hashes"

  # some projects, like amber, put one space between the hash and the name.
  if [ -n "${ONE_SPACE_MANIFEST:-}" ]; then
    sed -i.bak 's/  / /' "$BATS_TEST_TMPDIR/hashes"
  fi

  if [ "$manifest" = "$signature" ]; then
    sign_clear signer "$BATS_TEST_TMPDIR/hashes" "$signature"
  else
    cp "$BATS_TEST_TMPDIR/hashes" "$manifest"
    sign_detached signer "$manifest" "$signature"
  fi

  local extra_asset
  for extra_asset in "$@"; do
    echo "$extra_asset" > "$extra_asset"
  done

  jaq -n --arg tag "$tag" \
    '[{ tagName: $tag, publishedAt: "2026-01-01T00:00:00Z" }]' \
    > "$FAKE_GH_ROOT/releases.json"

  run "$repo_dir/packages/$package_name/verify.sh"
}

@test 'amber' {
  ONE_SPACE_MANIFEST=1 run_release amber v6.6.9 \
    manifest-v6.6.9.txt manifest-v6.6.9.txt.sig amber-universal-v6.6.9.apk \
    amber-fdroid-universal-v6.6.9.apk
  [ "$status" -eq 0 ]
  [ "$(published)" = 'amber-universal-v6.6.9.apk' ]
}

@test 'bitcoin knots' {
  run_release bitcoin_knots v29.4.2.knots20260508 SHA256SUMS SHA256SUMS.asc \
    bitcoin-29.4.2.knots20260508-x86_64-linux-gnu.tar.gz
  [ "$status" -eq 0 ]
  [ "$(published)" = 'bitcoin-29.4.2.knots20260508-x86_64-linux-gnu.tar.gz' ]
}

@test 'core lightning' {
  run_release core_lightning v26.06.9 SHA256SUMS-v26.06.9 \
    SHA256SUMS-v26.06.9.asc clightning-v26.06.9-Ubuntu-24.04-amd64.tar.xz \
    SHA256SUMS-v26.06.9-arm64 SHA256SUMS-v26.06.9-arm64.asc
  [ "$status" -eq 0 ]
  [ "$(published)" = 'clightning-v26.06.9-Ubuntu-24.04-amd64.tar.xz' ]
}

@test 'eclair' {
  run_release eclair v0.14.4 SHA256SUMS.asc SHA256SUMS.asc \
    eclair-node-0.14.4-397abfc-bin.zip
  [ "$status" -eq 0 ]
  [ "$(published)" = 'eclair-node-0.14.4-397abfc-bin.zip' ]
}

@test 'haven' {
  run_release haven v1.2.2 checksums.txt checksums.txt.sig \
    haven_Darwin_arm64.tar.gz
  [ "$status" -eq 0 ]
  [ "$(published)" = 'haven_Darwin_arm64.tar.gz' ]
}

@test 'liana' {
  run_release liana v15.0 liana-15.0-shasums.txt liana-15.0-shasums.txt.asc \
    liana-15.0-x86_64-linux-gnu.tar.gz
  [ "$status" -eq 0 ]
  [ "$(published)" = 'liana-15.0-x86_64-linux-gnu.tar.gz' ]
}

@test 'liana business' {
  run_release liana business-v1.0rc2 liana-business-1.0rc2-shasums.txt \
    liana-business-1.0rc2-shasums.txt.asc liana-business-1.0rc2-1_amd64.deb
  [ "$status" -eq 0 ]
  [ "$(published)" = 'liana-business-1.0rc2-1_amd64.deb' ]
}

@test 'lnd' {
  run_release lnd v0.21.4-beta manifest-v0.21.4-beta.txt \
    manifest-roasbeef-v0.21.4-beta.sig lnd-darwin-amd64-v0.21.4-beta.tar.gz \
    manifest-roasbeef-v0.21.4-beta.sig.ots
  [ "$status" -eq 0 ]
  [ "$(published)" = 'lnd-darwin-amd64-v0.21.4-beta.tar.gz' ]
}

@test 'phoenix' {
  run_release phoenix android-v2.8.4 SHA256SUMS.asc SHA256SUMS.asc \
    phoenix-120-2.8.4-mainnet.apk
  [ "$status" -eq 0 ]
  [ "$(published)" = 'phoenix-120-2.8.4-mainnet.apk' ]
}

@test 'seedsigner' {
  run_release seedsigner 0.8.7 seedsigner.0.8.7.sha256.txt \
    seedsigner.0.8.7.sha256.txt.sig seedsigner_os.0.8.7.pi0.img
  [ "$status" -eq 0 ]
  [ "$(published)" = 'seedsigner_os.0.8.7.pi0.img' ]
}

@test 'sparrow' {
  run_release sparrow 2.5.5 sparrow-2.5.5-manifest.txt \
    sparrow-2.5.5-manifest.txt.asc Sparrow-2.5.5-aarch64.dmg
  [ "$status" -eq 0 ]
  [ "$(published)" = 'Sparrow-2.5.5-aarch64.dmg' ]
}

@test 'specter desktop' {
  run_release specter_desktop v2.2.0-pre5 SHA256SUMS SHA256SUMS.asc \
    cryptoadvance_specter-2.2.0rc5.tar.gz
  [ "$status" -eq 0 ]
  [ "$(published)" = 'cryptoadvance_specter-2.2.0rc5.tar.gz' ]
}

@test 'specter diy' {
  run_release specter_diy v1.10.5 sha256.signed.txt sha256.signed.txt \
    initial_firmware_v1.10.5.bin
  [ "$status" -eq 0 ]
  [ "$(published)" = 'initial_firmware_v1.10.5.bin' ]
}

@test 'wasabi' {
  run_release wasabi v2.8.4 SHA256SUMS.asc SHA256SUMS.asc \
    Wasabi-2.8.4-arm64.AppImage SHA256SUMS Wasabi-2.8.4-arm64.AppImage.asc
  [ "$status" -eq 0 ]
  [ "$(published)" = 'Wasabi-2.8.4-arm64.AppImage' ]
}
