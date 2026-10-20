#!/usr/bin/env bash
# Flash AWTRIX NG onto the Ulanzi TC001. Full erase, then the merged USB image at 0x0.
set -euo pipefail
PORT="${PORT:-/dev/cu.usbserial-14130}"
BAUD="${BAUD:-115200}"   # faster rates are unreliable through the USB hub on this Mac
IMG="$(cd "$(dirname "$0")" && pwd)/awtrix-ng/usb-awtrix-ng-4mb.bin"
export PATH="$HOME/Library/Python/3.13/bin:$PATH"
esptool --chip esp32 --port "$PORT" --baud "$BAUD" erase-flash
esptool --chip esp32 --port "$PORT" --baud "$BAUD" write-flash 0x0 "$IMG"
