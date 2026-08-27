#!/bin/zsh
# Pure-logic tests: compiled and run directly, no GUI harness needed.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$ROOT/build"
swiftc -O \
  "$ROOT/Sources/EventTimeParser.swift" \
  "$ROOT/Sources/EventStore.swift" \
  "$ROOT/Scripts/tests/main.swift" \
  -o "$ROOT/build/parsertests"
"$ROOT/build/parsertests"
