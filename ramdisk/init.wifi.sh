#!/system/bin/sh
L="log -p i -t wifi-bringup"
MAC=$(/system/bin/sh /init.wifi_mac.sh)
if [ -n "$MAC" ]; then
    printf %s "$MAC" > /proc/wifi_built_in/mac_addr_hw && $L "factory MAC set from oeminfo"
else
    $L "no factory MAC from oeminfo; prima will autogenerate"
fi
/vendor/bin/wcnss_service &
for i in 1 2 3; do
    sleep 3
    echo start > /proc/wifi_built_in/wifi_start && break
    $L "driver start attempt $i failed"
done
[ -e /sys/class/net/wlan0 ] && $L "wlan0 up" || $L "wlan0 missing"
