#!/usr/bin/env bats

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup_file() {
  setup_keyring
}

teardown_file() {
  teardown_keyring
}

setup() {
  create_repo fdroid
  set_key_fingerprints fdroid "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  site="$FAKE_CURL_ROOT/f-droid.org/repo"
  mkdir -p "$site"
  local filename='org.fdroid.fdroid_2000053.apk'
  echo 'fdroid client apk' > "$site/$filename"
  sign_detached signer "$site/$filename" "$site/$filename.asc"
  local hash
  hash=$(shasum -a 256 "$site/$filename" | cut -d ' ' -f 1)
  jaq -n --arg filename "/$filename" --arg hash "$hash" '{
    packages: {"org.fdroid.fdroid": {versions: {release: {
      added: 1767225600000, manifest: {versionCode: 2000053},
      file: {name: $filename, sha256: $hash}
    }}}}
  }' > "$site/index-v2.json"
}

@test 'fdroid uses a versioned apk and its detached signature' {
  run "$repo_dir/packages/fdroid/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(published)" = 'org.fdroid.fdroid_2000053.apk' ]
  [ "$(state_of fdroid)" = '2026-01-01T00:00:00Z' ]
}

@test 'fdroid rejects an unexpected path in the repository index' {
  jaq '.packages["org.fdroid.fdroid"].versions.release.file.name =
    "/../outside.apk"' "$site/index-v2.json" > index.new
  mv index.new "$site/index-v2.json"
  run "$repo_dir/packages/fdroid/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of fdroid)" ]
}

set_fdroid_release_date() {
  local timestamp="$1"
  jaq --argjson timestamp "$timestamp" '
    .packages["org.fdroid.fdroid"].versions.release.added = $timestamp
  ' "$site/index-v2.json" > index.new
  mv index.new "$site/index-v2.json"
}

@test 'fdroid skips an old release with a missing signature' {
  rm "$site/org.fdroid.fdroid_2000053.apk.asc"
  run "$repo_dir/packages/fdroid/verify.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ "$(state_of fdroid)" = '2026-01-01T00:00:00Z' ]
}

@test 'fdroid waits up to one day for a missing signature' {
  set_fdroid_release_date "$(($(date -u +%s) * 1000))"
  rm "$site/org.fdroid.fdroid_2000053.apk.asc"
  run "$repo_dir/packages/fdroid/verify.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of fdroid)" ]
  [[ "$output" == *'waiting for the next run'* ]]
}

@test 'fdroid retries signature server errors without recording the release' {
  export FAKE_CURL_STATUS_FILE='org.fdroid.fdroid_2000053.apk.asc'
  export FAKE_CURL_STATUS=503
  run "$repo_dir/packages/fdroid/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of fdroid)" ]
}

@test 'fdroid retries signature timeouts without recording the release' {
  export FAKE_CURL_TRANSPORT_FAIL='org.fdroid.fdroid_2000053.apk.asc'
  run "$repo_dir/packages/fdroid/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of fdroid)" ]
}

@test 'fdroid fetches its index once and skips an older unsigned release' {
  local filename='org.fdroid.fdroid_2000054.apk'
  echo 'new client apk' > "$site/$filename"
  sign_detached signer "$site/$filename" "$site/$filename.asc"
  local hash
  hash=$(shasum -a 256 "$site/$filename" | cut -d ' ' -f 1)
  jaq --arg filename "/$filename" --arg hash "$hash" '
    .packages["org.fdroid.fdroid"].versions.newer = {
      added: 1767312000000, manifest: {versionCode: 2000054},
      file: {name: $filename, sha256: $hash}
    }
  ' "$site/index-v2.json" > index.new
  mv index.new "$site/index-v2.json"
  rm "$site/org.fdroid.fdroid_2000053.apk.asc"
  export FAKE_CURL_REQUEST_LOG="$BATS_TEST_TMPDIR/requests"
  run "$repo_dir/packages/fdroid/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(published)" = "$filename" ]
  [ "$(state_of fdroid)" = '2026-01-02T00:00:00Z' ]
  [ "$(grep -c '/index-v2.json$' "$FAKE_CURL_REQUEST_LOG")" -eq 1 ]
}
