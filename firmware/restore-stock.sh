#!/usr/bin/env bash
# Restore the original Ulanzi firmware from the full-chip backup taken on 2026-10-20.
# The backup is a raw 4MB dump starting at offset 0, so it is written back at 0x0.
set -euo pipefail

PORT="${PORT:-/dev/cu.usbserial-14130}"
BAUD="${BAUD:-230400}"
DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/Library/Python/3.13/bin:$PATH"

esptool --chip esp32 --port "$PORT" --baud "$BAUD" erase-flash
esptool --chip esp32 --port "$PORT" --baud "$BAUD" write-flash 0x0 "$DIR/tc001-stock-backup.bin"
