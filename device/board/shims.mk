# Shims for stock Huawei vendor blobs built against older Android releases
# (device/huawei/ags_w09/libshims). Build-time equivalent of the LD_PRELOAD in the
# sensors HAL rc.
TARGET_LD_SHIM_LIBS := \
    /vendor/lib64/libizat_core.so|libshim_procname.so:/vendor/lib/libizat_core.so|libshim_procname.so
