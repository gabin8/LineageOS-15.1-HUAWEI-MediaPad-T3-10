# vendor/huawei/ags_w09 (not a git repo) — remove the sleeping lights blob

`ags_w09-vendor.mk` copies the Huawei Nougat `lights.msm8937.so` (32 + 64 bit) onto the
same path the source-built `device/liblight` installs to. Drop both copy lines:

    sed -i '\#proprietary/vendor/lib\(64\)\?/hw/lights.msm8937.so:#d' vendor/huawei/ags_w09/ags_w09-vendor.mk

In `device/huawei/ags_w09/proprietary-files.txt`, comment out the two entries so
`extract-files.sh`/`setup-makefiles.sh` don't bring the blob back:

    # vendor/lib/hw/lights.msm8937.so
    # vendor/lib64/hw/lights.msm8937.so

## Other vendor blobs not to ship (removed from `ags_w09-vendor.mk`, commented in `proprietary-files.txt`)

| Blob / package | Why |
|---|---|
| `vendor/bin/bootstat`, `vendor/etc/init/bootstat.rc` | stale Android 8.0 copies; the rc resets `/data/misc/bootstat` to root:root → 8.1 bootstat aborts |
| `vendor/etc/init/rild.rc` | radio daemon; Wi-Fi only |
| `ims`, `imssettings`, `embms`, `qcrilmsgtunnel`, `dpmserviceapp`, `atfwd` (`PRODUCT_PACKAGES`) | Wi-Fi calling, LTE broadcast, RIL/AT/data-port plumbing; Wi-Fi only |
| `qti-logkit`, `access-qcom-logkit` (`PRODUCT_PACKAGES`) | Qualcomm engineering log tool, not on stock Oreo; NPE-crashes at boot without DIAG access |

Shims these blobs need live in `device/libshims` (`libshim_camera`, `libshim_procname`).
