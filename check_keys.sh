#!/usr/bin/env bash

# audits every package's listed keys: imported and usable, still published at
# the listed url, and no keys in a project's key folder that aren't listed. with
# --import, imports each listed key from its url first.

cd "$(dirname -- "$(realpath "$0")")" || exit 1

is_import=false
if [ "${1:-}" = '--import' ]; then
  is_import=true
fi

problem_count=0
warning_count=0

report_problem() {
  echo "  problem: $1"
  problem_count=$((problem_count + 1))
}

report_warning() {
  echo "  warning: $1"
  warning_count=$((warning_count + 1))
}

# prints "<fingerprint> <url>" for each key a package lists.
listed_keys() {
  local package_name="$1"

  sed -n -E "s/^  '([0-9A-F]{40})' # (https?:[^ ]+).*/\1 \2/p" \
    "packages/$package_name/verify.sh"
}

is_any_key_in_file() {
  local fingerprints="$1"
  local key_filename="$2"

  gpg --with-colons --show-keys "$key_filename" 2> /dev/null \
    | awk -F: -v fingerprints="$(tr '\n' ' ' <<< "$fingerprints")" '
    BEGIN {
      split(fingerprints, list, " ")
      for (i in list) listed[list[i]] = 1
    }
    $1 == "fpr" && ($10 in listed) { found = 1 }
    END { exit !found }
  '
}

import_key() {
  local fingerprint="$1"
  local key_filename="$2"

  # gpg-agent's socket path has a short length limit, so keep the keyring out of
  # the long default temp directory.
  local home
  home=$(mktemp -d /tmp/hasheus-from-gpg-keys.XXXXXX) || exit 1

  # import only the listed key, even when the file has others.
  GNUPGHOME="$home" gpg -q --batch --import "$key_filename" 2> /dev/null
  GNUPGHOME="$home" gpg --batch --export "$fingerprint" \
    | gpg -q --batch --import 2> /dev/null
  GNUPGHOME="$home" gpgconf --kill gpg-agent
  rm -rf "${home:?}"
}

# prints "ok", or why the key can't verify signatures.
key_status() {
  local fingerprint="$1"

  local colons
  if ! colons=$(gpg --with-colons --fixed-list-mode --list-keys "$fingerprint" \
    2> /dev/null); then
    echo "isn't imported"
    return
  fi

  local status
  status=$(awk -F: -v now="$(date +%s)" '
    function is_usable() {
      return $12 ~ /s/ && $2 !~ /[er]/ && ($7 == "" || $7 > now)
    }
    $1 == "pub" {
      validity = $2
      expires_at = $7
      if (is_usable()) can_sign = 1
    }
    $1 == "sub" && is_usable() { can_sign = 1 }
    END {
      is_expired = validity == "e" || (expires_at != "" && expires_at <= now)
      if (validity == "r") print "is revoked"
      else if (is_expired) print "expired on " expires_at
      else if (!can_sign) print "has no usable signing key"
      else print "ok"
    }
  ' <<< "$colons")

  if [[ "$status" == 'expired on '* ]]; then
    local expired_on
    expired_on=$(jaq -rn --argjson time "${status#expired on }" \
      '$time | strftime("%Y-%m-%d")')
    status="expired on $expired_on"
  fi

  echo "$status"
}

# prints "<owner>/<repo> <ref> <directory>" for a key in a folder on
# raw.githubusercontent.com, or nothing otherwise.
github_key_directory() {
  local url="$1"

  local path="${url#https://raw.githubusercontent.com/}"
  [ "$path" = "$url" ] && return

  local owner repo rest
  IFS=/ read -r owner repo rest <<< "$path"
  rest="${rest#refs/heads/}"

  local ref="${rest%%/*}"
  local key_path="${rest#*/}"

  # a key at the repo's root isn't in a key folder.
  [[ "$key_path" == */* ]] || return

  echo "$owner/$repo $ref ${key_path%/*}"
}

check_listed_keys() {
  local package_name="$1"
  local key_dir="$2"

  local fingerprint url
  while read -r fingerprint url; do
    local label="${url##*/}"

    # a keyserver lookup has no file name, so name the host instead.
    if [[ "$label" == *'?'* ]]; then
      label="${url#*://}"
      label="${label%%/*}"
    fi

    label="$label (${fingerprint: -16})"
    local key_filename="$key_dir/$fingerprint"

    if ! curl -fsSL --max-time 30 -o "$key_filename" "$url" 2> /dev/null; then
      report_problem "$label can no longer be downloaded from $url"
    elif ! is_any_key_in_file "$fingerprint" "$key_filename"; then
      report_problem "$label is no longer in $url"
    elif [ "$is_import" = true ]; then
      import_key "$fingerprint" "$key_filename"
    fi

    local status
    status=$(key_status "$fingerprint")

    case "$status" in
      ok) ;;
      "isn't imported" | 'is revoked') report_problem "$label $status" ;;
      *) report_warning "$label $status" ;;
    esac
  done < <(listed_keys "$package_name")
}

check_unlisted_keys() {
  local package_name="$1"
  local key_dir="$2"

  local listed_fingerprints listed_urls
  listed_fingerprints=$(listed_keys "$package_name" | cut -d ' ' -f 1)
  listed_urls=$(listed_keys "$package_name" | cut -d ' ' -f 2)

  local repo ref directory
  while read -r repo ref directory; do
    local listing
    if ! listing=$(gh api "repos/$repo/contents/$directory?ref=$ref"); then
      report_problem "couldn't list $repo/$directory to check for unlisted keys"
      continue
    fi

    local filename download_url
    while read -r filename download_url; do
      if grep -Fq "/$directory/$filename" <<< "$listed_urls"; then
        continue
      fi

      local key_filename="$key_dir/unlisted"
      if ! curl -fsSL --max-time 30 -o "$key_filename" "$download_url" \
        2> /dev/null; then
        report_problem \
          "couldn't download $repo/$directory/$filename to check it"
        continue
      fi

      # the same key can be in a folder under two names, like bitcoin core's
      # sedited.gpg and TheCharlatan.gpg.
      if ! is_any_key_in_file "$listed_fingerprints" "$key_filename"; then
        report_problem "$repo has $directory/$filename, which isn't listed"
      fi
    done < <(jaq -r '
      .[]
      | select(.type == "file" and (.name | test("\\.(asc|gpg|txt)$")))
      | "\(.name) \(.download_url)"
    ' <<< "$listing")
  done < <(
    while read -r url; do
      github_key_directory "$url"
    done <<< "$listed_urls" | sort -u
  )
}

key_dir=$(mktemp -d) || exit 1
trap 'rm -rf "$key_dir"' EXIT

for script in packages/*/verify.sh; do
  package_name="${script#packages/}"
  package_name="${package_name%/verify.sh}"

  echo "--- $package_name"

  check_listed_keys "$package_name" "$key_dir"
  check_unlisted_keys "$package_name" "$key_dir"
done

echo "--- $problem_count problems, $warning_count warnings"

[ "$problem_count" -eq 0 ]
