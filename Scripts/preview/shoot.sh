#!/bin/zsh
# Builds the preview harness, launches it, screenshots the window, quits.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/build/preview.png}"
APPEARANCE="${CALBAR_APPEARANCE:-dark}"

mkdir -p "$ROOT/build"
SRC=("$ROOT/Sources/PopoverChrome.swift" "$ROOT/Sources/CalendarViewModel.swift" "$ROOT/Sources/CalendarViews.swift" "$ROOT/Scripts/preview/main.swift")
[[ -f "$ROOT/Sources/Palette.swift" ]] && SRC+=("$ROOT/Sources/Palette.swift")

swiftc -swift-version 5 "${SRC[@]}" -o "$ROOT/build/CalBarPreview" || { echo "BUILD FAILED"; exit 1; }

pkill -f CalBarPreview 2>/dev/null || true
sleep 0.3
LOG="$ROOT/build/preview.log"
CALBAR_APPEARANCE="$APPEARANCE" CALBAR_CLEAR="${CALBAR_CLEAR:-0}" CALBAR_SELECT="${CALBAR_SELECT:-}" CALBAR_GOTO="${CALBAR_GOTO:-0}" CALBAR_EMPTY="${CALBAR_EMPTY:-0}" "$ROOT/build/CalBarPreview" > "$LOG" 2>&1 &
PID=$!
for i in {1..40}; do
  RECT=$(grep -m1 '^RECT ' "$LOG" 2>/dev/null | cut -d' ' -f2 || true)
  [[ -n "${RECT:-}" ]] && break
  sleep 0.25
done
[[ -n "${RECT:-}" ]] || { echo "no RECT emitted"; cat "$LOG"; kill $PID 2>/dev/null; exit 1; }
sleep 1.2
screencapture -o -x -R"$RECT" "$OUT"
kill $PID 2>/dev/null || true
echo "wrote $OUT ($RECT)"
