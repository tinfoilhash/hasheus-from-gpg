#!/usr/bin/env bash

cd "$(dirname -- "$(realpath "$0")")" || exit 1

status=0
package_count=0

while IFS= read -r -d '' script; do
  # give each script its own empty stdin so nothing it runs can consume the list
  # of scripts.
  "$script" < /dev/null || status=1
  package_count=$((package_count + 1))
  echo
done < <(find packages -name 'verify.sh' -type f -print0 | sort -z)

if [ "$package_count" -eq 0 ]; then
  echo 'no packages found, exiting'
  exit 1
fi

exit "$status"
