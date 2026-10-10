#!/bin/zsh
# Runs the unit tests (build products go to the local disk, see build.sh).
set -e
cd "$(dirname "$0")"
swift test --scratch-path "${BAMBULIGHT_BUILD_DIR:-$HOME/Library/Caches/BambuLight/build}" "$@"
