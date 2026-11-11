#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/directory.sh

check_dependencies

echo '--- verifying whonix'

repo='https://www.whonix.org/download'
key_fingerprints=(
  '916B8D99C38EAF5E8ADC7A2A8D66066A2EEACCDA' # https://www.whonix.org/keys/derivative.asc
)

list_release_assets() {
  directory_tree_assets "$1/$2/"
}

categories=$(read_directory "$repo/") || exit 1
# the root also has developer fixtures containing empty historical images.
categories=$(jaq -r '.[] | .name | select(. == "iso/" or . == "libvirt/"
  or . == "ova/" or . == "source/" or . == "windows/")' \
  <<< "$categories") || exit 1
if [ -z "$categories" ]; then
  echo 'whonix download categories are missing, exiting'
  exit 1
fi

# formats have independent release schedules; windows must not be hidden by
# newer virtual-machine images taking all three initial release slots.
category_root="$repo"
while IFS= read -r category <&6; do
  package_name="whonix_${category%/}"
  repo="$category_root/$category"
  verify_with_signed_files "$package_name" "${repo%/}" .asc \
    "${key_fingerprints[@]}"
done 6<<< "$categories"
