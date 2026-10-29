#!/system/bin/sh
# On-device build.prop fixes for an already-flashed image (a rebuilt ROM gets these from
# device/device-tree.patch). Stock identity values come from this unit's product/version partitions.
# Takes effect on the next boot. The ramdisk default.prop carries the matching bootimage fingerprint.
FP='HUAWEI/AGSEEA/HWAGS-Q:8.0.0/HUAWEIAGS-W09/150(C431):user/release-keys'
mount -o rw,remount /system; mount -o rw,remount /vendor
[ -f /system/build.prop.bak-redmi ] || cp /system/build.prop /system/build.prop.bak-redmi
[ -f /vendor/build.prop.bak-redmi ] || cp /vendor/build.prop /vendor/build.prop.bak-redmi
# identity (was the rolex/riva clone's)
sed -i -e 's|^ro.product.model=.*|ro.product.model=AGS-W09|' \
       -e 's|^ro.product.brand=.*|ro.product.brand=HUAWEI|' \
       -e 's|^ro.product.name=.*|ro.product.name=AGSEEA|' \
       -e 's|^ro.product.device=.*|ro.product.device=HWAGS-Q|' \
       -e 's|^ro.product.manufacturer=.*|ro.product.manufacturer=HUAWEI|' \
       -e 's|^ro.build.product=.*|ro.build.product=AGS|' \
       -e 's|^ro.build.description=.*|ro.build.description=AGS-W09-user 8.0.0 HUAWEIAGS-W09 150(C431) release-keys|' \
       -e "s|^ro.build.fingerprint=.*|ro.build.fingerprint=$FP|" \
       -e 's|^ro.build.characteristics=.*|ro.build.characteristics=tablet|' /system/build.prop
# vendor fingerprint must equal the system one; stock tablet density (320 made it a phone)
sed -i -e "s|^ro.vendor.build.fingerprint=.*|ro.vendor.build.fingerprint=$FP|" \
       -e 's|^ro.sf.lcd_density=.*|ro.sf.lcd_density=213|' /vendor/build.prop
# display flicker: Huawei hwcomposer describes the client target as RGBA8888-UBWC; MDSS 1.15 has no UBWC
sed -i 's/^debug.gralloc.enable_fb_ubwc=1/debug.gralloc.enable_fb_ubwc=0/' /vendor/build.prop
grep -q "^debug.gralloc.gfx_ubwc_disable=" /vendor/build.prop || echo "debug.gralloc.gfx_ubwc_disable=1" >> /vendor/build.prop
grep -q "^video.disable.ubwc=" /vendor/build.prop || echo "video.disable.ubwc=1" >> /vendor/build.prop
sync
