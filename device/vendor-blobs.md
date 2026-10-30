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

Shims these blobs need live in `device/libshims` (`libshim_procname`).

## Camera: stock EMUI 8.0 (Oreo) stack instead of the Nougat one

The Nougat (EMUI 5) camera userspace never produced frames on this port. The stock Oreo one
(HAL, `mm-qcamera-daemon`, libmmcamera2, chromatix, sensor/actuator/eeprom libs, camera XMLs)
does, together with the Oreo-era kernel driver (`kernel/oreo-camera-v2.patch`). Take it from the
AGS-W09 C185 Oreo `vendor.img` (mounted read-only), then silence its per-frame log spam:

    vendor/oreo-camera/swap-camera-blobs.py <lineage root> /mnt/oreo_vendor
    vendor/patch-camera-blobs.sh <lineage root>/vendor/huawei/ags_w09/proprietary/vendor/lib

The script removes the 916 Nougat-only camera files (`nougat-camera-remove.txt`), installs the
2103 Oreo ones (`oreo-camera-add.txt`) and updates `ags_w09-vendor.mk` and
`proprietary-files.txt` to match. It deliberately leaves out:

| Blob | Why |
|---|---|
| Oreo's `android.hardware.camera.provider@2.4-service` + rc, camera HIDL impls | built from source (AOSP provider on `/dev/vndbinder`) |
| `vendor/etc/init/init.huawei.camera.rc` | only starts `/system/bin/HwServiceHost`, which isn't on this system |
| `sensor_calibrate`, `lib_sensor_fac`, `libhuawei_sensor_test` | factory sensor-calibration tools, not camera |

It also installs `cpp_firmware_*.fw` to **`/vendor/firmware`**. The Nougat list put them in
`/vendor/etc/firmware`, which ueventd never searches, so the CPP (post-processing engine) never
got its firmware and the ISP couldn't map the preview/snapshot streams.
