#!/usr/bin/env bash

# runs every package. with LOG_DIR set, each package's output goes to
# $LOG_DIR/<package>.log, and its exit status to $LOG_DIR/status.txt as
# "<package> <status>".

cd "$(dirname -- "$(realpath "$0")")" || exit 1

if [ -n "${LOG_DIR:-}" ]; then
  mkdir -p "$LOG_DIR" || exit 1
  : > "$LOG_DIR/status.txt" || exit 1
fi

status=0
package_count=0

while IFS= read -r -d '' script; do
  package_name="${script#packages/}"
  package_name="${package_name%/verify.sh}"

  # give each script its own empty stdin so nothing it runs can consume the list
  # of scripts.
  if [ -n "${LOG_DIR:-}" ]; then
    "$script" < /dev/null > "$LOG_DIR/$package_name.log" 2>&1
  else
    "$script" < /dev/null
  fi
  package_status=$?

  if [ "$package_status" -ne 0 ]; then
    status=1
  fi

  if [ -n "${LOG_DIR:-}" ]; then
    echo "$package_name $package_status" >> "$LOG_DIR/status.txt"
  else
    echo
  fi

  package_count=$((package_count + 1))
done < <(find packages -name 'verify.sh' -type f -print0 | sort -z)

if [ "$package_count" -eq 0 ]; then
  echo 'no packages found, exiting'
  exit 1
fi

exit "$status"
