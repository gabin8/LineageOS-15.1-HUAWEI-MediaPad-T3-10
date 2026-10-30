#!/system/bin/sh
# AGS-W09 WCNSS (pronto) WiFi bring-up (stock: wcnss-service + wifi_driver_init).
# Runs in the wifi_bringup SELinux domain. /firmware and /persist come from fstab.qcom; the
# firmware path and the NV copy are done by init (init.qcom.rc). Order matters:
# wcnss_node_open() triggers the pronto PIL only once per boot and /dev/wcnss_ctrl can only be
# opened once per boot, so firmware, persist and the NV must be in place before wcnss_service runs.
L="log -p i -t wifi-bringup"
# Factory MAC (oeminfo id 0x34). Stock libhardware_legacy writes it to mac_addr_hw
# right before "start"; prima latches it in mac_param and uses it on every start
# (hdd_update_config_from_nv). Without it prima autogenerates 00:0a:f5 + SoC serial.
# Done before wcnss_service so the first-boot RSA step (~40 s, then cached) does
# not change the wcnss_service -> start timing.
MAC=$(/system/bin/sh /init.wifi_mac.sh)
if [ -n "$MAC" ]; then
    printf %s "$MAC" > /proc/wifi_built_in/mac_addr_hw && $L "factory MAC set from oeminfo"
else
    $L "no factory MAC from oeminfo; prima will autogenerate"
fi
/vendor/bin/wcnss_service &
# Pre-start prima like stock's wifi_driver_init; the WiFi HAL starts/stops it on demand afterwards
# (a second start is a no-op).
for i in 1 2 3; do
    sleep 3
    echo start > /proc/wifi_built_in/wifi_start && break
    $L "driver start attempt $i failed"
done
[ -e /sys/class/net/wlan0 ] && $L "wlan0 up" || $L "wlan0 missing"
