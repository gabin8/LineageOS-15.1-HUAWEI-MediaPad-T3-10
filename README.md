# LineageOS 15.1 for Huawei MediaPad T3 10 (AGS-W09 / "agassi")

**Status: BOOTS END-TO-END to the LineageOS setup wizard / launcher, with working WiFi.** system_server is stable,
SystemUI runs, the panel lights, HIDL/binder HALs register, storage mounts, and the LineageOS
Setup Wizard is interactive (Welcome → Locale → …). As far as I know this is the first time this
exact unit (Snapdragon T3, **not** the Kirin AGS2) has fully booted a from-source LineageOS.

- **Device:** Huawei MediaPad T3 10, model **AGS-W09** (Wi‑Fi only), codename **agassi / ags_w09**
- **SoC:** Qualcomm Snapdragon 425 / MSM8917 (msm8937 family), 4 cores, 2 GB RAM
- **Target:** LineageOS 15.1 (Android 8.1), 3.18 kernel
- ⚠️ **AGS-W09 (Snapdragon T3) is NOT AGS2-W09 (Kirin T5).** Do not cross-flash. Hard-brick risk.

## ⚠️ This unit runs a flashed engineering QRD bootloader

Not Huawei's stock bootloader (from earlier unlock work). It reports board-id **0x1000b** (QRD SKU5),
authenticates boot images against the genuine stock `/boot` signature (so a custom image is packed
with that signature appended → RSA fails → orange "unlocked" warning → boots anyway), and passes
`androidboot.mode=charger` on USB power.

- **Only `fastboot boot <img>` works — do NOT `fastboot flash boot`.** `fastboot boot` bypasses the
  signature check; booting from the partition enforces it, rejects our bad-sig image, and drops the
  SoC into Qualcomm emergency download mode (`05c6:900e`, black screen). Keep the stock `boot.bin`
  on the boot partition for safety and RAM-boot the custom image every time.

## What works / what doesn't

| Area | State |
|---|---|
| Kernel, SMP, memory, mounts (`/system` `/vendor` `/data` `/cache` via ramdisk `mount_all`) | ✅ |
| Android init, properties, SELinux (permissive), HIDL/binder, HALs register | ✅ |
| **Display panel** (BOE NT51017 9.6" 800p via lcdkit) + HWComposer/SurfaceFlinger, GPU composition (no flicker) | ✅ |
| **Live adb in the main boot** (FunctionFS gadget) | ✅ |
| **Full boot:** zygote → SystemUI → setup wizard / Trebuchet launcher | ✅ |
| Touch, power/volume keys (keylayout), no input stalls | ✅ |
| Stock identity (AGS-W09 / HUAWEI, tablet, density 213) | ✅ |
| Wi-Fi-only: no SIM icon (`ro.radio.noril`), no telephony features, on-screen navigation bar | ✅ |
| Tablet UI wording ("About tablet"), no dialer/SMS/SIM-toolkit apps (rebuilt system image) | ✅ |
| Real factory WiFi MAC (from `oeminfo`) | ✅ |
| Browser / WebView (Chromium 138) | ✅ |
| Charging | ✅ (slow on a PC USB port; ~1 A cap on a wall charger) |
| **Audio**: real Qualcomm HAL — speaker playback + built-in mics (recording 16/44.1/48 kHz, mono/stereo) | ✅ |
| Thermal mitigation (`thermal-engine`), `time_daemon` | ✅ |
| Hardware video decoder (Venus/OMX) | ⚠️ initialises now (device permissions fixed); playback not verified |
| Camera | 🔄 HAL loads, back + front enumerate (HAL3), no crashes; **preview not working yet** |
| Bluetooth | ❓ not brought up (`hciattach` from the vendor rc not ported) |
| **WiFi** (WCN3660B / pronto, prima built into the kernel): scan + connect, 2.4 + 5 GHz | ✅ |
| WiFi hotspot | ❓ untested (builtin prima ignores `fwpath`; AP mode needs `con_mode`) |
| Accelerometer + auto-rotate (mCube MC3xxx via the ADSP sensor core) | ✅ |
| GPS / real IZAT location | ❌ gnss is a stub HAL; QC location stack disabled (incompatible libs) |

## The fix chain (what it took to boot)

Ordered roughly as the boot progresses. Everything here is in this kit.

### Boot image / kernel
1. **Signed boot packaging** (`scripts/make_signed_boot.sh`) — pack kernel+ramdisk, append the
   genuine stock `/boot` RSA signature so the locked eng aboot jumps to it.
2. **DTB selection + ramoops** (`scripts/patch_dtb.py`) — set `qcom,board-id = <0x1000b>` so the eng
   aboot's libfdt selector picks our DTB; optional ramoops region for debugging.
3. **binder multi-device + scatter-gather** (`kernel/binder/`) — the stock 3.18 binder is pre-Android-7
   (single `/dev/binder`). Android 8.1 needs `hwbinder`/`vndbinder` + scatter-gather. Replaced the whole
   subsystem with the msm8937 lineage-15.1 one; only code change: `mmput_async`→`mmput`. Set
   `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"`.
4. *(optional)* **ambient capabilities backport** (`kernel/ambient-caps-3.18.patch`) — upstream v4.3
   `PR_CAP_AMBIENT`. **Not required to boot** (see the gid fix below — that was the real blocker), but it
   makes `init`'s `capabilities` lines work and lets `crash_dump` produce real tombstones on this 3.18
   kernel. Upstream `58319057b784` + `746bf6d64275`, rebased onto this tree (applies with zero fuzz).

### Ramdisk (`ramdisk/`)
5. **Charger mode** (`init.rc.charger.patch`) — force a normal boot from `on charger` (eng aboot flags
   USB power as charger mode).
6. **`/system` + `/vendor` mount** (`fstab.qcom`, `init.qcom.rc`) — non-Treble build; mount classically
   in second stage via `on fs: mount_all /fstab.qcom` (vendor FS lives on the **`vendor`** partition).
7. **dcheckroot panic** (`default.prop.README`) — replace the ramdisk `/default.prop` symlink with a
   real file to dodge a NULL-check bug in Huawei's `fs/proc/dcheck_root.c`.
8. **Live main-boot adb** (`default.prop`, `init.qcom.rc`, `init.usb.rc`) — three parts, all needed:
   `persist.sys.usb.config=adb` (was `none` → gadget had no functions, adbd never started); mount
   **FunctionFS** for adb under `on fs` (`f_ffs/aliases adb` + `mount functionfs adb …`) because this
   kernel's android_usb adb is ffs-backed (without it the host sees `error -32, unable to enumerate`);
   and start `adbd` **before** `android0/enable 1`. Enumerates `18d1:4ee7`, authorized via baked
   `/adb_keys`. **The main-boot serial is `0123456789ABCDEF`, different from fastboot/recovery `c6d3daad`.**
9. **cpuset population** (`init.qcom.rc`) — the device has 4 cores (0-3) but init.rc copies the initially
   empty root cpuset into the children → `cpus=""` → `system_server.setThreadGroupAndCpuset()` throws and
   crash-loops (DisplayManagerService). Write `0-3` to each of foreground/background/system-background/top-app.
10. **generic light HAL service** (`init.qcom.rc` defines `light-hal-2-0`) — the stock aw2013 light
    service opens a nonexistent `/sys/class/leds/blue` and crashes; use the generic AOSP
    `android.hardware.light@2.0-service` + `-impl.so` (built from `hardware/interfaces/light/2.0/default`)
    over the on-device `lights.msm8937.so`. Defined in the ramdisk because the `/vendor` `.rc` wasn't parsed.

### Vendor-side (`vendor/`) — applied on the `/vendor` partition (persist), scripts included
11. **★ THE boot blocker: `remove-qcom-diag-gid.sh` ★** — the permission XMLs map a permission to
    `gid="qcom_diag"`, which is **not** in this ROM's bionic AID table → `getGidForName` returns -1 →
    system-uid app procs launch with gid -1 → kernel `setgroups` EINVAL → the zygote child **aborts
    silently** (no logcat, no tombstone). Only `android.uid.system` (Settings / FallbackHome) and
    `android.uid.phone` (com.android.phone) hold it → exactly why the framework + SystemUI came up but
    the HOME / setup wizard never could. Remove the three `<group gid="qcom_diag"/>` lines.
12. **`disable-incompatible-qc-apps.sh`** — once (11) lets them start, these QC uid-1000 apps crash on
    A7-era vendor libs (e.g. `libizat_core.so` needs the missing symbol `get_process_name`) and take down
    system_server (they run in the system process → lock-screen↔boot-animation loop). Disable
    com.qualcomm.location, CNEService, dpmserviceapp, colorservice, svi, cabl. (GNSS = stub HAL.)
13. **`audio_policy_configuration.xml`** — stock Huawei policy minus the **FM tuner**, telephony devices
    and the remote-submix module. With the real HAL (`audio.primary.msm8937.so`), AudioPolicyManager
    test-opens every attached input at startup; for the FM tuner (and remote submix) the HAL returns a
    garbage input buffer size, AudioFlinger's `RecordThread::readInputParameters_l` mallocs ~3.9 GB, gets
    NULL and `memset`s it → audioserver crash-loop. The built-in mics work (verified with an AudioRecord
    test at 16/44.1/48 kHz, mono and stereo). The real HAL needs the ADSP booted (item 24) so the
    `msm8952-snd-card-mtp` card exists. (Also needed: the built `consumerir.default.so` and the `gnss@1.0`
    service on `/vendor` so IConsumerIr/IGnss register — system_server hard-blocks on them here.)
14. **`gpio-keys.kl`** → `/vendor/usr/keylayout/` — the power key (code 116) falls back to `Generic.kl`
    with no `WAKE` flag, so the button can't wake from doze. This adds `key 116 POWER WAKE`.
15. **`ro.sys.sdcardfs=false`** (in `/vendor/build.prop`) — the kernel's sdcardfs 2.1.3 rejects the 8.1
    sdcard daemon's mount options (`derive_gid`) → vold hangs "Waiting for FUSE to spin up". Force FUSE
    (the kernel has it) and vold's storage scan completes.

### Frameworks (`frameworks/`)
16. **`SetupWizard-null-ringtone-guard.patch`** — `EnableAccessibilityController` does
    `mTone.setStreamType()` with no null check; `RingtoneManager.getRingtone()` returns null (stub audio /
    transient first-boot) → the wizard NPE-crash-loops. Adds `if (mTone != null)`. Rebuild with
    `make LineageSetupWizard` (NOT `mmm` — the Tests module fails proguard) and replace
    `/system/priv-app/LineageSetupWizard/LineageSetupWizard.apk`.

### WiFi (`ramdisk/init.wifi.sh`, `ramdisk/init.qcom.rc`)
17. **prima is built into the kernel** (`CONFIG_PRONTO_WLAN=y`, `CONFIG_HUAWEI_WIFI_BUILTIN=y`) — no
    `wlan.ko`. The driver is started by writing `start` to `/proc/wifi_built_in/wifi_start`, and only
    after the WCNSS (pronto) subsystem is up. Getting it up needs, **in this order, before the first
    open of `/dev/wcnss_wlan`/`/dev/wcnss_ctrl`** (the kernel triggers the pronto PIL only once per boot
    and `wcnss_ctrl` can only be opened once per boot — a premature attempt poisons the boot):
    the `modem` partition mounted at `/firmware` (it holds `image/wcnss.mdt`+`.bNN`),
    `firmware_class.path=/firmware/image`, `persist` mounted at `/persist` (factory cal), and the NV
    under the name Huawei's `wcnss_service` derives from the hardware IDs
    (`/data/misc/wifi/nvbin/msm8937_303_0x00_0x01_0x00_nv.bin` ← `WCNSS_hw_wlan_nv_ags_w09.bin`).
    `/firmware` and `/persist` now come from `fstab.qcom` (item 24 needs them at early-boot);
    `init.wifi.sh` keeps fallback mounts and does the rest as a `late_start` oneshot, then runs `wcnss_service` and kicks
    the driver. (`/dev/block/bootdevice` doesn't exist on this build, so mounts use the platform by-name path.)
18. **Framework side** — `/vendor/etc/init/hw/init.qcom.rc` is never imported (`/init.rc` imports it
    before `/vendor` is mounted; top-level `/vendor/etc/init/*.rc` are still parsed later), so the ramdisk carries its `wpa_supplicant` service, the WiFi data dirs,
    and `chown wifi wifi /sys/module/wlan/parameters/fwpath` (the WiFi HAL writes `sta` there; without
    it: `Failed to change firmware mode` → `Failed to start HAL for client mode`).

### Display, input, identity (`device/`, `vendor/apply-buildprop-fixes.sh`)
19. **Flicker on touch** — the Huawei hwcomposer describes the GPU client target as RGBA8888-**UBWC**,
    but MSM8917 (MDSS 1.15) has no UBWC, so every GPU-composed frame fails validation and is flushed as
    a black frame. `debug.gralloc.gfx_ubwc_disable=1` (+ `video.disable.ubwc=1`, drop
    `debug.gralloc.enable_fb_ubwc=1`).
20. **~4 s UI/scroll freezes every ~10 s** — the Huawei `lights.msm8937.so` blob `usleep()`s inside
    `setLight`. BatteryService updates the battery LED on every battery tick while holding its lock;
    PowerManagerService waits on that while holding *its* lock; InputDispatcher's per-touch
    `userActivity()` waits on PMS → touch input stalls. Replaced by CAF liblight built from source
    (`device/liblight`; drop the blob per `device/vendor-blobs.md`).
21. **Identity** — the tree is a Xiaomi rolex/riva clone: `libinit_msm8917` force-set
    `ro.product.model=Redmi 5A` (+ the riva power profile) and the fingerprint was Xiaomi's. Now the
    stock values from this unit's `product`/`version` partitions (AGS-W09, HUAWEI, HWAGS-Q, AGSEEA,
    `tablet`); system/vendor/bootimage fingerprints must match or Android shows an "internal problem"
    dialog. **Density 213** (stock) instead of 320, which made the 800 px panel a ~400 dp *phone*.

### Wi-Fi-only tablet product (`device/device-tree.patch`)
22. The clienthax tree is a Redmi 4A/5A (phone) clone, so the build was a **phone**:
    - `lineage.mk` inherited `full_base_telephony.mk` + LineageOS `common_full_phone.mk` (Dialer,
      Messaging, SIM Toolkit, Cell Broadcast, Emergency Info, CallLogBackup, rild). Now `full_base.mk` +
      `common_full_tablet_wifionly.mk`; `TeleService`/`Telecom` (core) and `CarrierConfig` stay, as on stock.
    - Phone-vs-tablet **UI wording** ("About phone", "Phone storage", …) is chosen by aapt at build time
      from `PRODUCT_CHARACTERISTICS`; `ro.build.characteristics` alone can't change it. Now `tablet`.
    - `ro.radio.noril=true` (stock value) drops the mobile network type, which hides the SIM/signal
      icons; `config_voice_capable`/`config_sms_capable` = false; the GSM/CDMA hardware-feature XMLs
      are no longer installed.
    - **No navigation bar**: the overlay declared Redmi capacitive keys (`config_deviceHardwareKeys=83`,
      home+back+recents+volume) and never set `config_showNavigationBar`. Now volume-only (`64`) and
      `config_showNavigationBar=true`.

### More hardware and system fixes
23. **Real WiFi MAC** (`ramdisk/init.wifi_mac.sh`) — without it prima autogenerates
    `00:0a:f5` + the SoC serial (a "new device" for every router). Stock reads oeminfo record **id 0x34**,
    an RSA-2048-signed blob (Huawei public key in `lib_hw_wifi_chipset_qcom.so`; the MAC is plaintext
    bytes 5..0, byte-reversed), and writes `XX:XX:XX:XX:XX:XX` to `/proc/wifi_built_in/mac_addr_hw`
    right before `start`. The helper does the same from the partition at boot (RSA in plain `awk`,
    ~40 s once, then cached by the record's sha256 in `/data/misc/wifi/oeminfo_wifimac`). No MAC is
    stored in this repo. Note: this build's `/system/bin/awk` is broken (`substr`, `return`, unary
    minus, `!`), so the helper avoids them.
24. **Accelerometer / auto-rotate** — the mCube MC3xxx (I²C 0x4C) hangs off the **ADSP-owned** BLSP bus
    and is driven by the Qualcomm sensor core in the ADSP firmware, so Linux never sees it. Needed, all
    before the sensors HAL enumerates (it waits only 5 s for the SMGR service): `irsc_util` loading
    `/vendor/etc/sec_config` (with `CONFIG_IPC_ROUTER_SECURITY` every QMI send blocks until then), the ADSP
    booted (`echo 1 > /sys/kernel/boot_adsp/boot`, restart level `related`), and the `sensors.qcom`
    registry daemon — see `ramdisk/init.qcom.rc`. The HAL (`sensors.ssc.so` → `liblocationservice.so`
    → Huawei `libizat_core.so`) imports `get_process_name()`, which 8.1 libcutils dropped → a two-function
    shim preloaded into the HAL service (`vendor/sensors/`). Side effect: with the ADSP up, the
    `msm8952-snd-card-mtp` sound card registers too (prerequisite for real audio).
25. **logd at 100% CPU** — `logd.klogd` loops on `/dev/kmsg` on this 3.18 kernel. That one core ate the
    whole USB charging budget (the battery *discharged* ~20-75 mA while showing "Charging"; now
    charges). `persist.logd.kernel=false` / `ro.logd.kernel=false`; the kernel log stays in `dmesg`.
26. **No WebView → browser crash** — LineageOS purged the lineage-15.1 WebView LFS objects; the blob that
    could still be fetched is WebView 156 (`minSdk 29`), which PackageManager rejects on 8.1, so nothing
    provides a WebView. Use Chromium's own **SystemWebView 138.0.7204.0** (the last generation that supports
    Android 8, `minSdk 26`, arm64 + armeabi-v7a) from Google's `chromium-browser-snapshots` bucket,
    `Android_Arm64/1465695/chrome-android.zip` → `apks/SystemWebView.apk`
    (sha256 `2b19607ebb1a029408990dd6dcfe221e1eb17fb78756016345f3023cbe777b18`), as
    `external/chromium-webview/prebuilt/arm64/webview.apk`. It is a dev snapshot (Chromium debug signature,
    accepted because the build is userdebug; no auto-updates).

### Init, permissions and stock daemons (`ramdisk/`)
27. **bootstat crash** — stock vendor ships an **8.0** `bootstat.rc` that runs after the system's 8.1 one
    and resets `/data/misc/bootstat` to `root:root`; 8.1 bootstat (user `system`) then can't open it and
    aborts. Don't install the vendor copy (and stale `vendor/bin/bootstat`).
28. **init parses every file in `/vendor/etc/init`**, not only `*.rc` — renaming a file to `.rc.disabled`
    does *not* disable it. Move unwanted rc files out of the directory (e.g. `/vendor/etc/init-disabled/`).
    Also dropped there: `rild.rc` (Wi-Fi only).
29. **Vendor ueventd rules never applied** — ueventd reads `/vendor/ueventd.rc` before `/vendor` is
    mounted, so `/dev/video*`, `/dev/media*`, `/dev/v4l-subdev*`… stayed `root 0600` (hardware video
    decoder `EACCES`, camera unusable). The ramdisk carries them as `ueventd.qcom.rc`.
30. **Stock daemons from the never-imported vendor rc** — `thermal-engine` (otherwise nothing throttles
    the SoC), `time_daemon`, `qcamerasvr` (camera daemon) are defined in the ramdisk `init.qcom.rc`.
    Modem daemons (rild, netmgrd, qti, cnd, ims*, rmt_storage, tftp_server) are intentionally left out.
31. **debugfs** isn't mounted → system_server WTF "neither /proc/wakelocks nor /d/wakeup_sources exists";
    mounted at early-init.
32. **Vendor apps that don't belong on a Wi-Fi tablet / don't work here** — Qualcomm Logkit (engineering
    log tool; not on stock Oreo; NPE-crashes at boot without DIAG), Wi-Fi calling (ims, imssettings), LTE
    broadcast (embms), RIL tunnel, AT forwarding, data port mapper: disabled on device
    (`vendor/disable-incompatible-qc-apps.sh`) and removed from the vendor `PRODUCT_PACKAGES`.
33. **Camera (in progress)** — the Huawei HAL (`camera.msm8937.so`, Nougat-era) needed:
    a shim for the pre-8.1 `DisplayEventReceiver()` ctor and Huawei's `isLogEnabled()` plus a preloaded
    `libsensor.so` (SensorManager moved out of libgui in O) → `device/libshims`; a device copy of the
    provider service on **`/dev/binder`** (AOSP uses `/dev/vndbinder`, where SurfaceFlinger and the sensor
    service don't exist, so the HAL waited forever) → `device/camera-provider`; and **HAL3**
    (`persist.camera.HAL3.enabled=1`, as stock — the inherited `=0` puts it in HAL1 mode, where the HAL
    passes a non-`CameraDevice` cookie to 8.1's `sGetMemory` and crashes). Both cameras enumerate; the
    preview is still black. Known wart: the HAL looks up `display.qservice` (registered on vndbinder by
    the composer) on every open/close and waits ~4 s for it.

## Build & flash (outline)

> Assumes the clienthax LineageOS 15.1 tree builds for you and you have the engineering bootloader.

```bash
# 1. Kernel: drop kernel/binder/* into drivers/staging/android/, set the binder devices config,
#    (optionally) apply kernel/ambient-caps-3.18.patch, build Image.gz (GCC 4.9 aarch64).
# 2. DTB:  python3 scripts/patch_dtb.py <dtb> <out.dtb> --ramoops
# 3. Ramdisk: apply ramdisk/* (init.rc charger patch; init.qcom.rc, init.usb.rc, default.prop,
#    fstab.qcom as provided; real /default.prop file).
# 4. Sign:  scripts/make_signed_boot.sh  "Image.gz+dtb"  ramdisk.cpio.gz  boot.img  "<cmdline>"
# 5. Flash userspace, keep stock boot on the partition, RAM-boot the signed image:
fastboot flash system system.img && fastboot flash vendor vendor.img
fastboot flash boot <stock boot.bin>          # safe partition — do NOT flash the custom image
fastboot boot boot.img                          # RAM-boot (the ONLY path that works for our bad-sig img)
# 6. On device (adb, main-boot serial 0123456789ABCDEF), apply the /vendor fixes once:
adb shell 'mount -o rw,remount /vendor'
adb push vendor/gpio-keys.kl /vendor/usr/keylayout/gpio-keys.kl
adb push vendor/audio_policy_configuration.xml /vendor/etc/audio_policy_configuration.xml
adb push vendor/remove-qcom-diag-gid.sh vendor/disable-incompatible-qc-apps.sh /data/local/tmp/
adb shell 'sh /data/local/tmp/remove-qcom-diag-gid.sh; sh /data/local/tmp/disable-incompatible-qc-apps.sh'
#    (and: consumerir.default.so + android.hardware.gnss@1.0-service/-impl + the generic light service,
#     all built from AOSP; see fixes 10 & 13.)
adb push vendor/apply-buildprop-fixes.sh /data/local/tmp/ && adb shell sh /data/local/tmp/apply-buildprop-fixes.sh
#    shims (device/libshims, built with the tree) → /vendor/lib{,64}; replace
#    /vendor/etc/init/android.hardware.sensors@1.0-service.rc with vendor/sensors/'s copy; install the
#    device camera provider (device/camera-provider) and move unwanted rc files to /vendor/etc/init-disabled.
# For a reproducible build: apply device/device-tree.patch, add device/liblight and device/configs to the device tree,
# drop the lights blob (device/vendor-blobs.md), fold 11-15 into the vendor image, and apply 16.
```

## Remaining work (help wanted)
- **WiFi hotspot:** untested; `WCNSS_qcom_cfg_ags.ini` (the Huawei per-device variant) vs the generic
  `WCNSS_qcom_cfg.ini` currently used is worth comparing.
- **Camera preview** (item 33): HAL loads and both cameras enumerate, preview still black.
- **Release-key signing**: the build uses AOSP test keys (Trust warns "signed with public keys").
- **SELinux enforcing**: still permissive; needs policy for the added services and stock blobs.
- **Bluetooth**, **GPS**: not brought up.
- Make all the on-device fixes part of the vendor/system image for a one-shot flash.

## Credits & license
Built on the GPLv2 Linux kernel and the clienthax and LineageOS sources; the ambient-caps patch is
upstream (Andy Lutomirski, v4.3). Shared in the same spirit — use at your own risk, no warranty.
Flashing firmware can brick your device.
