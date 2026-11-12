#!/usr/bin/env bats

# bats runs each test with its own fixture environment.
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup_file() {
  setup_keyring
}

teardown_file() {
  teardown_keyring
}

prepare_maven_release() {
  local package_name="$1"
  local group="$2"
  local artifact="$3"
  local version="$4"
  create_repo "$package_name"
  set_key_fingerprints "$package_name" "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  local base="$FAKE_CURL_ROOT/repo.maven.apache.org/maven2/$group/$artifact"
  mkdir -p "$base/$version"
  cat > "$base/index.html" << EOF
<html><pre><a href="../">../</a>
<a href="$version/">$version/</a> 2026-10-06 00:16 -
</pre></html>
EOF
  local suffix
  echo '<html><pre><a href="../">../</a>' > "$base/$version/index.html"
  for suffix in jar sources.jar pom; do
    local filename="$artifact-$version.$suffix"
    [ "$suffix" = sources.jar ] && filename="$artifact-$version-sources.jar"
    echo "$filename" > "$base/$version/$filename"
    sign_detached signer "$base/$version/$filename" \
      "$base/$version/$filename.asc"
    echo "<a href=\"$filename\">$filename</a> 2026-10-06 00:16 10" \
      >> "$base/$version/index.html"
    echo "<a href=\"$filename.asc\">$filename.asc</a> 2026-10-06 00:16 10" \
      >> "$base/$version/index.html"
  done
  echo '</pre></html>' >> "$base/$version/index.html"
}

prepare_tied_maven_releases() {
  prepare_maven_release bdk_jvm org/bitcoindevkit bdk-jvm 3.1.1
  tied_base="$FAKE_CURL_ROOT/repo.maven.apache.org/maven2/org/bitcoindevkit"
  tied_base+="/bdk-jvm"
  mkdir -p "$tied_base/3.1.2"
  cat > "$tied_base/index.html" << HTML
<pre>
<a href="3.1.1/">3.1.1/</a> 2026-10-06 00:16 -
<a href="3.1.2/">3.1.2/</a> 2026-10-06 00:16 -
</pre>
HTML
  local filename='bdk-jvm-3.1.2.pom'
  echo "$filename" > "$tied_base/3.1.2/$filename"
  sign_detached signer "$tied_base/3.1.2/$filename" \
    "$tied_base/3.1.2/$filename.asc"
  cat > "$tied_base/3.1.2/index.html" << HTML
<pre>
<a href="$filename">$filename</a> 2026-10-06 00:16 10
<a href="$filename.asc">$filename.asc</a> 2026-10-06 00:16 10
</pre>
HTML
  set_state bdk_jvm '2026-10-05T00:00:00Z'
}

prepare_nextcloud_server() {
  create_repo nextcloud_server
  set_key_fingerprints nextcloud_server "$(fingerprint_of signer)"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  local base="$FAKE_CURL_ROOT/download.nextcloud.com/server/releases"
  mkdir -p "$base"
  echo '<html><table><tr><th>name</th></tr>' > "$base/index.html"
  local version suffix day=6
  for version in 32.0.0 32.0.1 32.0.2; do
    for suffix in tar.bz2 zip; do
      local filename="nextcloud-$version.$suffix"
      echo "$filename" > "$base/$filename"
      sign_detached signer "$base/$filename" "$base/$filename.asc"
      echo "<tr><td><a href=\"$filename\">$filename</a></td>" \
        "<td>2026-10-0$day 00:16</td></tr>" >> "$base/index.html"
      echo "<tr><td><a href=\"$filename.asc\">sig</a></td>" \
        "<td>2026-10-0$day 00:16</td></tr>" >> "$base/index.html"
    done
    day=$((day + 1))
  done
  echo '</table></html>' >> "$base/index.html"
}

@test 'bdk jvm verifies signed maven artifacts and sources' {
  prepare_maven_release bdk_jvm org/bitcoindevkit bdk-jvm 3.1.1
  run "$repo_dir/packages/bdk_jvm/verify.sh"
  [ "$status" -eq 0 ]
  published_is 'bdk-jvm-3.1.1-sources.jar bdk-jvm-3.1.1.jar bdk-jvm-3.1.1.pom'
  [ "$(state_of bdk_jvm)" = '2026-10-06T00:16:00Z' ]
}

@test 'directory discovery fails on a challenge page' {
  prepare_maven_release bdk_jvm org/bitcoindevkit bdk-jvm 3.1.1
  local base="$FAKE_CURL_ROOT/repo.maven.apache.org/maven2/org/bitcoindevkit"
  echo '<html>please sign in</html>' > "$base/bdk-jvm/index.html"
  run "$repo_dir/packages/bdk_jvm/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of bdk_jvm)" ]
}

@test 'ldk node jvm reuses signed maven artifact discovery' {
  prepare_maven_release ldk_node_jvm org/lightningdevkit ldk-node-jvm 0.7.0
  run "$repo_dir/packages/ldk_node_jvm/verify.sh"
  [ "$status" -eq 0 ]
  local expected='ldk-node-jvm-0.7.0-sources.jar ldk-node-jvm-0.7.0.jar'
  published_is "$expected ldk-node-jvm-0.7.0.pom"
  [ "$(state_of ldk_node_jvm)" = '2026-10-06T00:16:00Z' ]
}

@test 'directory discovery does not use a folder without a valid date' {
  prepare_maven_release bdk_jvm org/bitcoindevkit bdk-jvm 3.1.1
  local index="$FAKE_CURL_ROOT/repo.maven.apache.org/maven2/org/bitcoindevkit"
  index="$index/bdk-jvm/index.html"
  sed 's/2026-10-06 00:16/not-a-date/' "$index" > index.new
  mv index.new "$index"
  run "$repo_dir/packages/bdk_jvm/verify.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_HASHEUS_LOG" ]
  [ -z "$(state_of bdk_jvm)" ]
}

@test 'directory discovery understands apache, openwrt and whonix dates' {
  create_repo bdk_jvm
  # shellcheck source=common/directory.sh
  source "$repo_dir/common/directory.sh"
  export FAKE_CURL_ROOT="$BATS_TEST_TMPDIR/site"
  mkdir -p "$FAKE_CURL_ROOT/index.example"
  local date
  for date in '2026-10-06 00:16' 'Tue Oct  6 00:16:00 2026' \
    '2026-Oct-06 00:16'; do
    cat > "$FAKE_CURL_ROOT/index.example/index.html" << HTML
<html><table><tr><th>name</th><th>date</th></tr>
<tr><td><a href="3.1.1/">3.1.1/</a></td><td>$date</td></tr>
</table></html>
HTML
    run read_directory https://index.example/
    [ "$status" -eq 0 ]
    [ "$(jaq -r '.[0].publishedAt' <<< "$output")" = \
      '2026-10-06T00:16:00Z' ]
  done
}

@test 'tied releases keep their checkpoint until every release succeeds' {
  prepare_tied_maven_releases
  local file="$tied_base/3.1.2/bdk-jvm-3.1.2.pom"
  sign_detached stranger "$file" "$file.asc"
  run "$repo_dir/packages/bdk_jvm/verify.sh"
  [ "$status" -eq 1 ]
  [ "$(state_of bdk_jvm)" = '2026-10-05T00:00:00Z' ]
  [ "$(wc -l < "$FAKE_HASHEUS_LOG" | tr -d ' ')" -eq 3 ]
  sign_detached signer "$file" "$file.asc"
  run "$repo_dir/packages/bdk_jvm/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(state_of bdk_jvm)" = '2026-10-06T00:16:00Z' ]
  [ "$(wc -l < "$FAKE_HASHEUS_LOG" | tr -d ' ')" -eq 4 ]
}

@test 'tied releases report bad files once after checking their siblings' {
  prepare_tied_maven_releases
  echo 'tampered' >> "$tied_base/3.1.1/bdk-jvm-3.1.1.pom"
  run "$repo_dir/packages/bdk_jvm/verify.sh"
  [ "$status" -eq 1 ]
  [ "$(state_of bdk_jvm)" = '2026-10-06T00:16:00Z' ]
  published_is 'bdk-jvm-3.1.1-sources.jar bdk-jvm-3.1.1.jar bdk-jvm-3.1.2.pom'
  run "$repo_dir/packages/bdk_jvm/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$FAKE_HASHEUS_LOG" | tr -d ' ')" -eq 3 ]
}

@test 'tied releases wait for recent missing files without advancing state' {
  prepare_tied_maven_releases
  local date
  date=$(date -u '+%Y-%m-%d %H:%M')
  sed "s/2026-10-06 00:16/$date/g" "$tied_base/index.html" > index.new
  mv index.new "$tied_base/index.html"
  local index="$tied_base/3.1.2/index.html"
  cp "$index" "$index.complete"
  sed '/[.]asc/d' "$index" > index.new
  mv index.new "$index"
  run "$repo_dir/packages/bdk_jvm/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(state_of bdk_jvm)" = '2026-10-05T00:00:00Z' ]
  mv "$index.complete" "$index"
  run "$repo_dir/packages/bdk_jvm/verify.sh"
  [ "$status" -eq 0 ]
  [ "$(state_of bdk_jvm)" != '2026-10-05T00:00:00Z' ]
  [ "$(wc -l < "$FAKE_HASHEUS_LOG" | tr -d ' ')" -eq 4 ]
}

@test 'nextcloud server groups all formats before limiting releases' {
  prepare_nextcloud_server
  run "$repo_dir/packages/nextcloud_server/verify.sh"
  [ "$status" -eq 0 ]
  local expected='nextcloud-32.0.0.tar.bz2 nextcloud-32.0.0.zip'
  expected+=' nextcloud-32.0.1.tar.bz2 nextcloud-32.0.1.zip'
  expected+=' nextcloud-32.0.2.tar.bz2 nextcloud-32.0.2.zip'
  published_is "$expected"
  [ "$(state_of nextcloud_server)" = '2026-10-08T00:16:00Z' ]
}

@test 'nextcloud server leaves an unverified release pending' {
  prepare_nextcloud_server
  local base="$FAKE_CURL_ROOT/download.nextcloud.com/server/releases"
  sign_detached stranger "$base/nextcloud-32.0.2.zip" \
    "$base/nextcloud-32.0.2.zip.asc"
  run "$repo_dir/packages/nextcloud_server/verify.sh"
  [ "$status" -eq 1 ]
  [ "$(state_of nextcloud_server)" = '2026-10-07T00:16:00Z' ]
}
