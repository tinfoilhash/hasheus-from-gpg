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

  # some, like alby hub, list the manifest itself with an empty file's hash.
  if [ -n "${SELF_LISTED_MANIFEST:-}" ]; then
    shasum -a 256 /dev/null | sed "s| .*|  ./$manifest|" \
      >> "$BATS_TEST_TMPDIR/hashes"
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

# writes a fake release <tag> with the asset signed as <asset><suffix>, for
# projects that sign each file. any further arguments are extra assets that
# aren't signed.
run_signed_files_release() {
  local package_name="$1"
  local tag="$2"
  local suffix="$3"
  local asset="$4"
  shift 4

  create_repo "$package_name"
  set_key_fingerprints "$package_name" "$(fingerprint_of signer)"

  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  export FAKE_GH_ROOT="$FAKE_CURL_ROOT/github.example"

  local release_dir="$FAKE_GH_ROOT/$tag"
  mkdir -p "$release_dir"
  cd "$release_dir" || exit 1

  echo "$asset" > "$asset"
  sign_detached signer "$asset" "$asset$suffix"

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

@test 'alby hub' {
  SELF_LISTED_MANIFEST=1 run_release alby_hub v1.24.3 \
    manifest.txt manifest.txt.asc albyhub-Server-Linux-aarch64.tar.bz2 \
    manifest-rolznz.txt.asc
  [ "$status" -eq 0 ]
  [[ "$output" == *'file is the manifest itself, skipping'* ]]
  [ "$(published)" = 'albyhub-Server-Linux-aarch64.tar.bz2' ]
}

@test 'bisq' {
  run_signed_files_release bisq v1.10.9 .asc Bisq-64bit-1.10.9.deb \
    E222AA02.asc signingkey.asc
  [ "$status" -eq 0 ]
  [ "$(published)" = 'Bisq-64bit-1.10.9.deb' ]
}

@test 'bisq 2' {
  run_signed_files_release bisq_2 v2.1.14 .asc Bisq-2.1.14.dmg \
    387C8307.asc signingkey.asc
  [ "$status" -eq 0 ]
  [ "$(published)" = 'Bisq-2.1.14.dmg' ]
}

@test 'bitboxapp' {
  run_signed_files_release bitboxapp v4.52.0 .asc BitBox-4.52.0-android.apk
  [ "$status" -eq 0 ]
  [ "$(published)" = 'BitBox-4.52.0-android.apk' ]
}

@test 'bitcoin keeper' {
  run_release bitcoin_keeper v2.6.3 SHA256SUM.asc SHA256SUM.asc \
    Bitcoin_Keeper_v2.6.3.apk SHA256SUM KEEPER_DETACHED_SIGN.sign
  [ "$status" -eq 0 ]
  [ "$(published)" = 'Bitcoin_Keeper_v2.6.3.apk' ]
}

@test 'bitcoin knots' {
  run_release bitcoin_knots v29.4.2.knots20260508 SHA256SUMS SHA256SUMS.asc \
    bitcoin-29.4.2.knots20260508-x86_64-linux-gnu.tar.gz
  [ "$status" -eq 0 ]
  [ "$(published)" = 'bitcoin-29.4.2.knots20260508-x86_64-linux-gnu.tar.gz' ]
}

@test 'bitcoin safe' {
  run_signed_files_release bitcoin_safe 2.1.3 .asc \
    Bitcoin-Safe-2.1.3-x86_64.AppImage.tar.gz
  [ "$status" -eq 0 ]
  [ "$(published)" = 'Bitcoin-Safe-2.1.3-x86_64.AppImage.tar.gz' ]
}

@test 'blockstream green' {
  run_release blockstream_green release_3.6.0 SHA256SUMS.asc SHA256SUMS.asc \
    Blockstream-x86_64.AppImage Blockstream-arm64.dmg
  [ "$status" -eq 0 ]
  [ "$(published)" = 'Blockstream-x86_64.AppImage' ]
}

@test 'chantools' {
  run_release chantools v0.14.3 manifest-v0.14.3.txt manifest-v0.14.3.sig \
    chantools-linux-amd64-v0.14.3.tar.gz
  [ "$status" -eq 0 ]
  [ "$(published)" = 'chantools-linux-amd64-v0.14.3.tar.gz' ]
}

@test 'citrine' {
  ONE_SPACE_MANIFEST=1 run_release citrine v3.2.0 \
    manifest-v3.2.0.txt manifest-v3.2.0.txt.sig citrine-universal-v3.2.0.apk \
    citrine-fdroid-universal-v3.2.0.apk
  [ "$status" -eq 0 ]
  [ "$(published)" = 'citrine-universal-v3.2.0.apk' ]
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

@test 'elements' {
  run_release elements elements-23.3.4 SHA256SUMS.asc SHA256SUMS.asc \
    elements-23.3.4-x86_64-linux-gnu.tar.gz SHA256SUMS
  [ "$status" -eq 0 ]
  [ "$(published)" = 'elements-23.3.4-x86_64-linux-gnu.tar.gz' ]
}

@test 'faraday' {
  run_release faraday v0.2.14-alpha manifest-v0.2.14-alpha.txt \
    manifest-v0.2.14-alpha.sig faraday-linux-amd64-v0.2.14-alpha.tar.gz
  [ "$status" -eq 0 ]
  [ "$(published)" = 'faraday-linux-amd64-v0.2.14-alpha.tar.gz' ]
}

@test 'frigate' {
  run_release frigate 1.6.1 frigate-1.6.1-manifest.txt \
    frigate-1.6.1-manifest.txt.asc frigate_1.6.1_amd64.deb
  [ "$status" -eq 0 ]
  [ "$(published)" = 'frigate_1.6.1_amd64.deb' ]
}

@test 'fulcrum' {
  run_release fulcrum v2.1.3 Fulcrum-2.1.3-shasums.txt \
    Fulcrum-2.1.3-shasums.txt.asc Fulcrum-2.1.3-x86_64-linux.tar.gz
  [ "$status" -eq 0 ]
  [ "$(published)" = 'Fulcrum-2.1.3-x86_64-linux.tar.gz' ]
}

@test 'haven' {
  run_release haven v1.2.2 checksums.txt checksums.txt.sig \
    haven_Darwin_arm64.tar.gz
  [ "$status" -eq 0 ]
  [ "$(published)" = 'haven_Darwin_arm64.tar.gz' ]
}

@test 'krux' {
  run_release krux v26.09.0 SHA256SUMS SHA256SUMS.asc krux-v26.09.0.zip \
    SHA256SUMS.sig
  [ "$status" -eq 0 ]
  [ "$(published)" = 'krux-v26.09.0.zip' ]
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

@test 'lightning terminal' {
  run_release lightning_terminal v0.17.7 manifest-v0.17.7.txt \
    manifest-roasbeef-v0.17.7.sig \
    lightning-terminal-linux-amd64-v0.17.7.tar.gz \
    manifest-roasbeef-v0.17.7.sig.ots
  [ "$status" -eq 0 ]
  [ "$(published)" = 'lightning-terminal-linux-amd64-v0.17.7.tar.gz' ]
}

@test 'lnd' {
  run_release lnd v0.21.4-beta manifest-v0.21.4-beta.txt \
    manifest-roasbeef-v0.21.4-beta.sig lnd-darwin-amd64-v0.21.4-beta.tar.gz \
    manifest-roasbeef-v0.21.4-beta.sig.ots
  [ "$status" -eq 0 ]
  [ "$(published)" = 'lnd-darwin-amd64-v0.21.4-beta.tar.gz' ]
}

@test 'loop' {
  run_release loop v0.35.0-beta manifest-v0.35.0-beta.txt \
    manifest-v0.35.0-beta.txt.sig loop-linux-amd64-v0.35.0-beta.tar.gz
  [ "$status" -eq 0 ]
  [ "$(published)" = 'loop-linux-amd64-v0.35.0-beta.tar.gz' ]
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

@test 'taproot assets' {
  run_release taproot_assets v0.8.6 manifest-v0.8.6.txt \
    manifest-roasbeef-v0.8.6.sig taproot-assets-linux-amd64-v0.8.6.tar.gz \
    manifest-roasbeef-v0.8.6.sig.ots
  [ "$status" -eq 0 ]
  [ "$(published)" = 'taproot-assets-linux-amd64-v0.8.6.tar.gz' ]
}

@test 'trezor suite' {
  run_signed_files_release trezor_suite v26.9.3 .asc \
    Trezor-Suite-26.9.3-linux-x86_64.AppImage latest-linux.yml \
    Trezor-Suite-26.9.3-mac-arm64.dmg.blockmap
  [ "$status" -eq 0 ]
  [ "$(published)" = 'Trezor-Suite-26.9.3-linux-x86_64.AppImage' ]
}

@test 'wasabi' {
  run_release wasabi v2.8.4 SHA256SUMS.asc SHA256SUMS.asc \
    Wasabi-2.8.4-arm64.AppImage SHA256SUMS Wasabi-2.8.4-arm64.AppImage.asc
  [ "$status" -eq 0 ]
  [ "$(published)" = 'Wasabi-2.8.4-arm64.AppImage' ]
}

@test 'zeus' {
  run_release zeus v13.2.3 manifest-v13.2.3.txt manifest-v13.2.3.txt.sig \
    zeus-v13.2.3-universal.apk
  [ "$status" -eq 0 ]
  [ "$(published)" = 'zeus-v13.2.3-universal.apk' ]
}
