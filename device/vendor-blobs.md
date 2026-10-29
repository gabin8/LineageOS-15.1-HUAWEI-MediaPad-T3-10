# vendor/huawei/ags_w09 (not a git repo) — remove the sleeping lights blob

`ags_w09-vendor.mk` copies the Huawei Nougat `lights.msm8937.so` (32 + 64 bit) onto the
same path the source-built `device/liblight` installs to. Drop both copy lines:

    sed -i '\#proprietary/vendor/lib\(64\)\?/hw/lights.msm8937.so:#d' vendor/huawei/ags_w09/ags_w09-vendor.mk

In `device/huawei/ags_w09/proprietary-files.txt`, comment out the two entries so
`extract-files.sh`/`setup-makefiles.sh` don't bring the blob back:

    # vendor/lib/hw/lights.msm8937.so
    # vendor/lib64/hw/lights.msm8937.so
