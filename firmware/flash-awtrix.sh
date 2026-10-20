#!/usr/bin/env bash
# Flash AWTRIX 3 onto the Ulanzi TC001.
# Erases the whole chip first (required on first install per AWTRIX docs),
# then writes the four images at the offsets from the AWTRIX web-flasher manifest.
set -euo pipefail

PORT="${PORT:-/dev/cu.usbserial-14130}"
BAUD="${BAUD:-230400}"   # 460800+ corrupts through the USB hub on this Mac
DIR="$(cd "$(dirname "$0")" && pwd)/awtrix"
export PATH="$HOME/Library/Python/3.13/bin:$PATH"

esptool --chip esp32 --port "$PORT" --baud "$BAUD" erase-flash
esptool --chip esp32 --port "$PORT" --baud "$BAUD" write-flash \
  0x1000  "$DIR/bootloader.bin" \
  0x8000  "$DIR/partitions.bin" \
  0xe000  "$DIR/boot_app0.bin" \
  0x10000 "$DIR/firmware.bin"
