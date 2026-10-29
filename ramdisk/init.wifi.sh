#!/system/bin/sh
# AGS-W09 WCNSS (pronto) WiFi bring-up.
# Order matters: wcnss_node_open() triggers the pronto PIL only once per boot and
# /dev/wcnss_ctrl can only be opened once per boot, so firmware, persist and the
# NV must be in place before wcnss_service runs.
L="log -p i -t wifi-bringup"
BN=/dev/block/platform/soc/7824900.sdhci/by-name
mount -t vfat -o ro,shortname=lower,uid=1000,gid=1000,dmask=227,fmask=337 $BN/modem /firmware
mount -t ext4 -o nosuid,nodev,noatime $BN/persist /persist
echo /firmware/image > /sys/module/firmware_class/parameters/path
# Huawei first-boot NV provisioning: wcnss_service wants a hardware-ID-named copy.
NV=/data/misc/wifi/nvbin/msm8937_303_0x00_0x01_0x00_nv.bin
mkdir -p /data/misc/wifi/nvbin
[ -f $NV ] || cp /vendor/etc/wifi/WCNSS_hw_wlan_nv_ags_w09.bin $NV
chown -R wifi:wifi /data/misc/wifi/nvbin
chmod 0644 $NV
$L "firmware/persist mounted, fw path set, NV $(ls $NV 2>&1)"
/vendor/bin/wcnss_service &
for i in 1 2 3; do
    sleep 3
    echo start > /proc/wifi_built_in/wifi_start && break
    $L "driver start attempt $i failed"
done
[ -e /sys/class/net/wlan0 ] && $L "wlan0 up" || $L "wlan0 missing"
