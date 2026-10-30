#!/usr/bin/env bash
# Use stock EMUI 8 (Oreo) OMX (video/audio codec) and ACDB (audio calibration) blobs instead of the
# Nougat ones. Huawei's Oreo gralloc and audio HAL are already in use on this port; the Nougat
# libOmxVdec reads gralloc1 handles with the old layout (every output buffer "size 1920" -> no
# hardware video decoding) and the Nougat libacdbloader lacks the v3 API the Oreo audio HAL calls
# (ACDB never initialised -> no speaker/mic calibration).
#   usage: use-oreo-blobs.sh tree   <lineage root> <mounted stock Oreo vendor.img>
#          use-oreo-blobs.sh device <mounted stock Oreo vendor.img>     (adb root; backs up first)
set -euo pipefail
HERE=$(dirname "$(realpath "$0")"); LIST=$HERE/oreo-media-audio-blobs.txt
case "${1:-}" in
tree)
    ROOT=$2 OREO=$3; P=$ROOT/vendor/huawei/ags_w09/proprietary; MK=$ROOT/vendor/huawei/ags_w09/ags_w09-vendor.mk
    while read -r f; do
        install -D -m 644 "$OREO/${f#vendor/}" "$P/$f"
        grep -q "proprietary/$f:" "$MK" || sed -i "/^PRODUCT_COPY_FILES += \\\\/a\\    vendor/huawei/ags_w09/proprietary/$f:\$(TARGET_COPY_OUT_VENDOR)/${f#vendor/} \\\\" "$MK"
    done < "$LIST"
    echo "tree: $(wc -l < "$LIST") Oreo blobs in place" ;;
device)
    OREO=$2; A="adb shell"; B=/data/local/tmp/oreo_media_audio_backup
    $A "mount -o remount,rw /vendor && mkdir -p $B/lib $B/lib64"
    while read -r f; do
        p=/vendor/${f#vendor/}
        $A "[ -f $p ] && cp -p $p $B/${f#vendor/}" </dev/null || true
        adb push "$OREO/${f#vendor/}" "$p" >/dev/null </dev/null
    done < "$LIST"
    $A "chmod 644 /vendor/lib/libOmx* /vendor/lib64/libOmx* /vendor/lib*/libacdb* /vendor/lib*/libaudcal.so /vendor/lib*/libadiertac.so; restorecon -R /vendor/lib /vendor/lib64; sync"
    echo "device: done (backup in $B); reboot" ;;
*) sed -n 2,10p "$0"; exit 1 ;;
esac
