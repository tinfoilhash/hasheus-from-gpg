#!/usr/bin/env bash

cd "$(dirname -- "$(realpath "$0")")" || exit 1

status=0

while IFS= read -r -d '' script; do
  # Give each script its own empty stdin so nothing it runs can consume the list of scripts.
  "$script" < /dev/null || status=1
  echo
done < <(find packages -name 'verify.sh' -type f -print0 | sort -z)

exit "$status"
