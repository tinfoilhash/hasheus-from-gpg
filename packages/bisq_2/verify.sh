#!/usr/bin/env bash

package_dir=$(dirname -- "$(realpath "$0")")
cd "$package_dir" || exit 1

source ../../common/github.sh

check_dependencies

echo '--- verifying bisq 2'

package_name='bisq_2'
repo='bisq-network/bisq2'
key_fingerprints=(
  'B493319106CC3D1F252E19CBF806F422E222AA02' # https://bisq.network/pubkey/E222AA02.asc
  'B8A5D214ADFAA387A14C8BCF02AA2BAE387C8307' # https://bisq.network/pubkey/387C8307.asc
)
signature_suffix='.asc'

verify_signed_files_from_github "$package_name" "$repo" "$signature_suffix" \
  "${key_fingerprints[@]}"
