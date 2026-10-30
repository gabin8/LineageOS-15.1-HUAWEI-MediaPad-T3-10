#!/usr/bin/env bash
# Silence per-frame debug spam in the stock Huawei EMUI 8 (Oreo) camera blobs.
#   usage: patch-camera-blobs.sh <vendor/lib dir>
# libmmcamera2_iface_modules.so: iface_util_hw_notify_sof logs
#   "SOF event frame_id N , sof_frame_id N-1" at ERROR level on EVERY frame (~10-30/s),
#   flooding logcat. The log call is gated only by the IFACE error-level switch, so
#   the 'cbz r0' at 0x16e0a becomes an unconditional 'b.n' over that one call; every
#   other IFACE error stays visible.
set -euo pipefail
LIB="${1:?vendor/lib dir}/libmmcamera2_iface_modules.so"
ORIG=0cfb91af51bf6d79
sum=$(sha256sum "$LIB" | cut -c1-16)
[ "$(xxd -s 0x16e0a -l 2 -p "$LIB")" = "12e0" ] && { echo "already patched"; exit 0; }
[ "$sum" = "$ORIG" ] || { echo "unexpected $LIB (sha256 $sum), not patching" >&2; exit 1; }
printf '\x12\xe0' | dd of="$LIB" bs=1 seek=$((0x16e0a)) conv=notrunc status=none
echo "patched $LIB"
