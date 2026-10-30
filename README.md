# LineageOS 15.1 for HUAWEI MediaPad T3 10 (AGS-W09, codename "agassi")

**Status: daily-usable.** LineageOS 15.1 boots to the launcher and has WiFi, audio (speaker + mics),
both cameras, auto-rotate, charging and WebView. See the table below for what's left. As far as
I know this is the first time this exact unit (Snapdragon T3, **not** the Kirin AGS2) has fully booted a from-source LineageOS.

- **Device:** Huawei MediaPad T3 10, model **AGS-W09** (Wi‑Fi only), codename **agassi / ags_w09**
- **SoC:** Qualcomm Snapdragon 425 / MSM8917 (msm8937 family), 4 cores, 2 GB RAM
- **Target:** LineageOS 15.1 (Android 8.1), 3.18 kernel
- ⚠️ **AGS-W09 (Snapdragon T3) is NOT AGS2-W09 (Kirin T5).** Do not cross-flash. Hard-brick risk.

**Download (test build):** [v15.1-20261030](https://github.com/gabin8/LineageOS-15.1-HUAWEI-MediaPad-T3-10/releases/tag/v15.1-20261030): one zip with the RAM-boot image, system, vendor and product images, kernel source and `INSTALL.txt`. Needs the engineering bootloader; read `INSTALL.txt` first (the boot image is only ever `fastboot boot`ed).

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
| Android init, properties, HIDL/binder, HALs register | ✅ |
| **SELinux enforcing**: no denials in a boot + camera/audio/WiFi/sensors/browser run | ✅ |
| **Signed with private release keys** (no Trust "public keys" warning) | ✅ |
| **Display panel** (BOE NT51017 9.6" 800p via lcdkit) + HWComposer/SurfaceFlinger, GPU composition (no flicker) | ✅ |
| **Live adb in the main boot** (FunctionFS gadget) | ✅ |
| **Full boot:** zygote → SystemUI → setup wizard / Trebuchet launcher | ✅ |
| Touch, power/volume keys (keylayout), no input stalls | ✅ |
| Stock identity (AGS-W09 / HUAWEI, tablet, density 213); About shows **HUAWEI MediaPad T3 10 (AGS-W09)** | ✅ |
| Wi-Fi-only: no SIM icon (`ro.radio.noril`), no telephony features, on-screen navigation bar | ✅ |
| Tablet UI wording ("About tablet"), no dialer/SMS/SIM-toolkit apps (rebuilt system image) | ✅ |
| Real factory WiFi MAC (from `oeminfo`) | ✅ |
| Browser / WebView (Chromium 138) | ✅ |
| Charging (SMB1360; same driver and limits as stock: ≤1.2 A input, 1.2 A into the battery) | ✅ (input is AICL-limited by the source/cable, e.g. 450-600 mA on a PC/hub port) |
| **Audio**: real Qualcomm HAL — speaker playback + built-in mics (recording 16/44.1/48 kHz, mono/stereo), Huawei's agassi ACDB calibration loaded | ✅ |
| Thermal mitigation (`thermal-engine`), `time_daemon` | ✅ |
| **Hardware video decoding** (Venus): H.264, HEVC, VP8 up to 1080p30 (VP9 in software); Big Buck Bunny/Sintel/Tears of Steel with sound: 0–1% dropped frames | ✅ |
| **Camera**: rear 5 MP (s5k5e8, autofocus, factory OTP calibration) + front 2 MP (sp2509v) — preview and photos, stock EMUI 8 camera stack | ✅ |
| Bluetooth | ❓ not brought up (`hciattach` from the vendor rc not ported) |
| **WiFi** (WCN3660B / pronto, prima built into the kernel): scan + connect, 2.4 + 5 GHz | ✅ |
| WiFi hotspot | ❓ untested (builtin prima ignores `fwpath`; AP mode needs `con_mode`) |
| Accelerometer + auto-rotate (mCube MC3xxx via the ADSP sensor core); lock screen rotates too (Settings → Display → Rotate lock screen) | ✅ |
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
    **Driver start/stop like stock** (`device/device-tree.patch` board/wlan.mk,
    `frameworks/libwifi_hal-operstate-fstate-init.patch`). WiFi stayed *off after every boot*:
    WifiService enables WiFi ~17 s into boot, but prima only finishes loading (`wlan0` appears) at ~19 s,
    so the HAL failed `Could not read interface state for wlan0 (No such device)` three times and gave
    up until WiFi was toggled by hand. Stock solves this in its Huawei-modified `libwifi-hal`. On enable
    it sets `wlan.driver.trigger=start`, init writes `/proc/wifi_built_in/wifi_start`, and the HAL waits
    for the driver. On disable it sends `stop`. Stock also pre-starts the driver at boot with
    `wifi_driver_init`, our `init.wifi.sh`. LineageOS's HAL has the same mechanism as board flags:
    `WIFI_DRIVER_STATE_CTRL_PARAM=/proc/wifi_built_in/wifi_start` (`start`/`stop`) and
    `WIFI_DRIVER_OPERSTATE_PATH=/sys/class/net/wlan0/operstate`, which waits up to 12.5 s for `wlan0`.
    The ramdisk gives the HAL (user `wifi`) the node. prima serialises writes on a mutex and treats a
    second `start` as a no-op, so the boot pre-start and the HAL's start can't collide. The patch
    initialises `fstate` in `is_wifi_driver_ready()`, which LineageOS leaves undefined on a timeout.
    Result: WiFi is up a few seconds after boot. Turning it off unloads prima (saves power) and turning
    it on reloads it in ~0.4 s.

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
    The marketing name is stock's too: `ro.config.marketing_name=HUAWEI MediaPad T3 10` (from the
    `product` partition). `frameworks/Settings-show-marketing-name.patch` makes Settings → About show
    "HUAWEI MediaPad T3 10 (AGS-W09)". `ro.product.model` stays `AGS-W09` for apps and the fingerprint.

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
    whole USB charging budget: the battery *discharged* while showing "Charging". The kernel log stays in
    `dmesg`. The switch has to be **`ro.logd.kernel=false` in the ramdisk `default.prop`**: logd decides
    on klogd once, at `post-fs`, before `/data` persist props exist. `persist.logd.kernel=false` alone
    silently stops working after a reboot. The early-bring-up `bootlog` service (`logcat -b all -f
    /cache/bootlog.txt`) is gone from the ramdisk too: it filled `/cache` (250 MB) and held ~550 MB of RAM
    and a core. Measured on a 600 mA-limited USB port with the screen on: from −130…−420 mA to
    +275 mA into the battery.
    Charging itself works like stock. The stock Oreo kernel has the same Huawei AGS SMB1360 driver
    (AC input capped at 1.2 A, fast charge 1.2 A through the 10 mΩ sense resistor, AICL threshold
    4.5 V); stock userspace (`chargemonitor`) can only lower it. On a weak source or a thin cable,
    AICL settles lower; read it from `/sys/kernel/debug/smb1360` register `0x48` (low 7 bits index
    300, 400, 450, 500, 600 … 1500 mA). `current_now` is negative while the battery charges.
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
33. **Camera: stock EMUI 8.0 (Oreo) camera stack on an Oreo-era kernel driver.** The Nougat (7.0)
    camera userspace never got frames (the HAL needed gralloc/`DisplayEventReceiver` shims and still
    received ~0 fps). Stock Oreo's vendor camera stack works, once the pieces below it match:
    - **Kernel camera UAPI** (`kernel/oreo-camera-v2.patch`). The Oreo daemon is built against the
      Oreo-era `camera_v2` interface: `SUB_MODULE_MAX` 14 (IR LED / IR cut added), so
      `VIDIOC_MSM_SENSOR_INIT_CFG` / `VIDIOC_MSM_SENSOR_CFG` are 204/168 bytes instead of 188/152,
      plus changed ISP/CPP ioctls. With the Nougat driver every probe ioctl hit `default:`, so no
      sensor probed and Huawei's product-name query came back empty (`camera_config_.xml`). The patch
      replaces `drivers/media/platform/msm/camera_v2` and the camera UAPI headers with Huawei's Oreo
      driver from the LDN (Y7 Prime 2018, msm8937) kernel. The stock AGS Oreo kernel is the same
      unified Huawei msm89xx build. On top of that it ports back Huawei's AGS in-kernel **sensor OTP**
      readers (`sensor_otp_ags_s5k5e8.c`, `…hi553.c`, …) and their `CFG_GET_OTP_FLAG` /
      `CFG_SET_{AFC,AWB,LSC}_OTP_INFO` handlers. Without them the daemon's AF calibration fails and
      init aborts. Every ioctl number the Oreo libs use was checked against the new headers
      (compiled for 32-bit ARM). Camera debug logging is off in the defconfig, as on stock.
    - **Oreo blobs** in place of Nougat's (`vendor/oreo-camera/`, see `device/vendor-blobs.md`).
    - **CPP firmware** in `/vendor/firmware`: the vendor list installed it to `/vendor/etc/firmware`,
      which ueventd never searches (`cpp_firmware_v1_5_0.fw … could not find firmware`). Without it
      CPP doesn't initialise and the ISP can't map the streams.
    - **Provider back on `/dev/vndbinder`** (stock AOSP service; the Oreo HAL has no SurfaceFlinger or
      sensor-service dependency). The HAL looks up `display.qservice`, which lives there; on
      `/dev/binder` every camera open waited 4 s for it. Open now takes 190 ms.
    - `/data/vendor/camera` (daemon sockets, AEC/banding data) created by the ramdisk;
      `persist.vendor.camera.HAL3.enabled=1` and `perflock.enable=0`, since Oreo reads
      `persist.vendor.camera.*` and there is no perf daemon.
    - `vendor/patch-camera-blobs.sh`: a 2-byte patch removing the iface module's per-frame
      `SOF event frame_id …` ERROR log (~10-30 lines/s whenever a camera runs). Huawei's
      `init.huawei.camera.rc` is dropped (it only starts the absent `HwServiceHost`).
    Remaining daemon messages match stock: optional libs stock doesn't ship either (`sw_tnr`,
    `ppeiscore`, `llvd_smore`), no hardware face-detect node, the camkit XML probe falling back to the
    legacy config, Huawei's ERROR-level `Enter/Exit` and `PROFILE_*` traces. Image tuning is Huawei's
    own chromatix for these modules. Snap (API1/HAL1 by default) previews and shoots on both cameras.

### Kernel stability
34. **Kernel oops → watchdog reboot on WiFi resume** (`kernel/prima-mdns-filter-oops.patch`). Huawei's
    prima declares `wlan_hdd_set_filter(hdd_context_t*, pRequest, sessionId)` in
    `wlan_hdd_early_suspend.c` (a newer Qualcomm signature), but this tree defines it as
    `wlan_hdd_set_filter(hdd_adapter_t*, pRequest)`. The mDNS filter code passed the HDD *context*
    where an *adapter* is expected → garbage HAL handle → NULL-ish dereference in
    `sme_ReceiveFilterClearFilter` whenever Android left WiFi suspend mode (`SETSUSPENDMODE 0`) —
    `Unable to handle kernel NULL pointer dereference at 00000004`, then a watchdog bite (~2 h uptime).
    Fixed by passing the adapter; verified with `wpa_cli driver SETSUSPENDMODE 1/0` loops.

### Security
35. **SELinux enforcing** (`device/sepolicy/`, merged into the device tree's `sepolicy/`). The policy
    sits in the ramdisk (`/sepolicy`, `*_contexts`) on this non-Treble build, so every step was a
    RAM-boot. The logd audit rate limit (20/s) drops records, so it took a few permissive rounds before
    the enforcing ones. What it needed:
    - **Labels.** Partitions are only reachable as `/dev/block/platform/soc/7824900.sdhci/by-name/*`
      (labelled for system/vendor/userdata/cache/persist/misc/boot/recovery/modem/oeminfo), and the
      cmdline gets stock's `androidboot.bootdevice=7824900.sdhci`. `/firmware` is mounted with stock's
      `context=u:object_r:firmware_file:s0`. `genfscon` covers `/proc/wifi_built_in`, Huawei's
      `hw_audio_info` sysfs and the gpio LEDs (`sysfs_leds`). `/dev/hwlog_*` gets a device type. Files
      pushed by hand inherit their directory's label, so run `restorecon -R /vendor` after pushing
      blobs: that is what puts the camera daemon in `mm-qcamerad` and the light HAL in
      `hal_light_default` instead of `init`, and gives the GPU libs `same_process_hal_file`.
    - **`init.wifi.sh` in its own `wifi_bringup` domain** instead of `su`. It may read oeminfo
      (factory MAC), cache in `/data/misc/wifi`, write `/proc/wifi_built_in`, and exec
      `wcnss_service`. The NV copy and the firmware path moved into `init.qcom.rc`, and the fallback
      mounts are gone (fstab has them).
    - **Oreo camera:** `persist.vendor.camera.*` → `camera_prop`, `/data/vendor/camera`, and Huawei's
      `IHwCameraResourceService` hwservice.
    - **Sensors / auto-rotate.** The sensors HAL rc `LD_PRELOAD`s `libshim_procname`. Under enforcing
      the init → `hal_sensors_default` transition sets `AT_SECURE` and the linker silently drops
      `LD_PRELOAD`. AOSP `dontaudit`s that, so nothing is logged and the HAL just comes up with 0
      sensors (the screen stays portrait). `allow init hal_sensors_default:process noatsecure;`
      fixes it.
    - Small rules for the WiFi HAL (`wifi_start`), thermal-engine sockets, mediaextractor on fuse and
      `com.qualcomm.timeservice` (runs as `system_app`). Apps enumerating properties (Chromium) are
      `dontaudit`ed.

36. **Release keys.** The build was signed with AOSP's *test* keys, whose private halves are public, so
    anyone could sign an app the system trusts as `android.uid.system`. LineageOS Trust warns about that
    ("This build was signed with public keys"; it checks `ro.build.tags`). The fix is your own keys, not
    a different tag:
    - Make `releasekey`, `platform`, `shared` and `media` once with AOSP's `development/tools/make_key`
      into `~/.android-certs` (0700, outside every repo; this repo also `.gitignore`s key files, and
      local pre-commit/pre-push hooks refuse them). Back them up. If they're lost, the next build can't
      update an installed system without migrating again.
    - `mka target-files-package` (run `make installclean` first, or files the tree dropped stay in
      `out/` and `vendor.img` overflows its 736 MB partition), then `scripts/sign-build.sh <root>`
      (`sign_target_files_apks` + `img_from_target_files`). The tags become `release-keys`.
    - **Keep your apps and data:** installed packages remember the test certificates in
      `/data/system/packages.xml`, and shared-UID system apps would fail to load. With the framework
      stopped (`adb shell stop`), `scripts/migrate-package-certs.py` swaps the four certificates
      (testkey→releasekey, platform, shared, media). Also remove `/data/system/package_cache`, then
      flash `system`.
    - Done here with `system` only: this unit's `/vendor` still differs from the tree (stock Oreo
      graphics/audio blobs, disabled TrustZone modules, …; see Remaining work). So its 11 vendor APKs
      were replaced by the signed ones from the build, and the 8 Qualcomm apps the tree no longer ships
      were removed. Only AOSP's presigned, permission-less CTS shims keep a test signature.

### Media
37. **Hardware video decoding** (`vendor/oreo-media-audio/`, `device/vendor-blobs.md`). Every hardware
    decode failed with "Can't play this video". `libOmxVdec` started, Venus booted, then each output
    buffer was rejected: `Invalid filled length = 3133440, buffer size = 1920`. The Nougat OMX blobs read
    the Oreo gralloc's handles with the old layout, the same bug class as the Nougat camera HAL. The
    stock EMUI 8 OMX set fixes it. MSM8917 decodes **H.264 (incl. secure), HEVC and VP8 in hardware, up
    to 1920x1088 at 244,800 MB/s (1080p30), 20 Mbit/s**, and encodes H.264 at the same limit. MPEG-4,
    H.263 and VP9 decode in software; VP9 1080p takes ~3 of 4 cores. Measured with CC BY clips (Blender
    Foundation): Sintel 1080p24 0 dropped frames, Sintel trailer 2/738, Tears of Steel 720p 0/1471, at
    ~3–6% codec CPU. 1080p60 H.264 is past the hardware limit and doesn't play.
38. **Audio calibration** (same blob set + `/product`). The stock Oreo audio HAL calls the v3 ACDB API,
    which the Nougat `libacdbloader` lacks (`undefined symbol: acdb_loader_init_v3`). It also looks
    for this tablet's tuning in `/product/etc/acdbdata/agassi` (product identifier "agassi"): speaker,
    handset, headset and Bluetooth `.acdb` files, mixer paths and platform info, on Huawei's
    **product** partition. So ACDB never initialised (`ACDB -> Not correctly initialized!`,
    `q6asm_send_cal: cal_block is NULL`) and the DSP played uncalibrated. With the Oreo ACDB libraries
    and `/product` mounted read-only from the ramdisk `fstab.qcom`, the HAL loads all seven agassi
    calibration files and sends speaker calibration on playback.
39. **MP3 audio in QuickTime/MOV** (`frameworks/MPEG4Extractor-quicktime-mp3.patch`): Android 8.1's
    extractor drops `.mp3`/`ms U` sound sample entries, so e.g. Blender's Tears of Steel `.mov` played
    silent. Backported from AOSP 10's `MPEG4Extractor`: map them to `audio/mpeg`, skip the QuickTime
    v1/v2 sound-description extension for every QuickTime audio entry, ignore atoms inside `wave`.
40. **Eleven ANR on media keys** (`frameworks/Eleven-media-button-foreground.patch`). Since 2018
    upstream starts `MusicPlaybackService` with `startForegroundService()` from the media button
    receiver, but the service only calls `startForeground()` when playback starts. Pause or stop with
    nothing playing then ends in an ANR (or a `RemoteServiceException` when the command stops the
    service). This was never fixed upstream before Eleven was replaced by Twelve. The service now
    enters the foreground right away for media-button starts and leaves it again unless playing.
41. **Lock screen stuck in portrait** after every reboot: not a sensor problem. Like stock,
    `config_enableLockScreenRotation` is true for `sw600dp`, but LineageOS also requires its own
    "Rotate lock screen" setting (`lineagesettings` `lockscreen_rotation`), which defaults to off.
    Turn it on in Settings → Display.
42. **Older HEVC files rejected** (`frameworks/Utils-hevc-hvcC-version0.patch`): Android 8.1 refuses an
    HEVC track whose `hvcC` record has configurationVersion 0 (`E Utils: b/23680780`, "Can't play this
    video") before any decoder starts. Early HEVC muxers wrote 0, e.g. libde265.org's HEVC encodes of
    Sintel and Big Buck Bunny. Backported from AOSP 10: accept 0 as well as 1.
43. **`StreamHAL: Error from HAL stream in function get_presentation_position: Operation not permitted`**
    (`frameworks/audio-StreamOut-presentation-position-EPERM.patch`, `hardware/interfaces`): logged twice per
    output start and ~50 times in a row when e.g. ExoPlayer opens a track. AudioFlinger polls the position
    while the HAL stream is still in standby; CAF's HAL returns `-ENODATA` then, which the HIDL wrapper
    already ignores, but Huawei's blob returns `-1`. Same `INVALID_STATE` result either way (steady playback
    never fails), so the wrapper now ignores `EPERM` too.
44. **Stale JIT profiles after re-flashing system** (`zygote64: Checksum mismatch for dex SystemUI.apk`,
    about once a minute). The build keeps Huawei's stock `ro.build.fingerprint`, so Android never sees an
    upgrade and keeps the old profiles of apps whose code changed. ART then refuses to merge new samples
    (dex checksum differs), so the profile never updates and background dexopt can't precompile those apps'
    hot code. After flashing a changed system, reset them: `adb shell cmd package compile --reset -a` (or per
    package). Found on Settings, SystemUI, Eleven, Jelly and LineageParts.
45. **Screen lock (PIN/pattern/password) could not be set** (`device/device-tree.patch`). The vendor manifest
    declared `android.hardware.gatekeeper@1.0`, but Huawei's gatekeeper needs its TrustZone app, which this
    unit's TZ doesn't provide (the TZ modules are set aside). `gatekeeperd` blocked forever in
    `IGatekeeper::getService()` ("Waited one second ... Waiting another", every second) and never registered
    its service, so LockSettings had no gatekeeper. Dropping only the manifest entry is not enough: libhidl
    then loads the passthrough `android.hardware.gatekeeper@1.0-impl`, which aborts ("Unable to open
    GateKeeper HAL"). With the entry and `product/gatekeeper.mk` (impl + service) removed, `gatekeeperd`
    falls back to AOSP's software GateKeeper; set/verify/clear PIN works. On an existing install: remove the
    `<hal>` block from `/vendor/manifest.xml` and `/vendor/lib{,64}/hw/android.hardware.gatekeeper@1.0-impl.so`.
46. **Phantom fingerprint support**: Huawei's shared vendor set ships `android.hardware.fingerprint.xml`
    though the T3 10 has no sensor, so FingerprintService kept looking for a HAL. Not shipped any more
    (`device/vendor-blobs.md`).
47. **AudioFX (equalizer) never attached to playback** (`frameworks/lineage-sdk-audio-session-broadcast-background.patch`):
    `BroadcastQueue: Background execution not allowed: receiving ... ACTION_AUDIO_SESSIONS_CHANGED to
    org.lineageos.audiofx/.receiver.ServiceDispatcher` on every new audio session. On 8.1 a manifest receiver
    of an app targeting O+ never gets an implicit broadcast unless it is flagged `FLAG_RECEIVER_INCLUDE_BACKGROUND`
    (or needs a signature permission; `OBSERVE_AUDIO_SESSIONS` is `normal`), even while the app runs. Backported
    lineage-sdk `dc5d872a2f` from lineage-16.0, which adds the flag. Now delivered, and each new session gets
    AudioFX's chain (Equalizer, Virtualizer, Preset Reverb, Bass Boost).

## Build & flash (outline)

> Assumes the clienthax LineageOS 15.1 tree builds for you and you have the engineering bootloader.

```bash
# 1. Kernel: drop kernel/binder/* into drivers/staging/android/, set the binder devices config,
#    apply kernel/prima-mdns-filter-oops.patch and kernel/oreo-camera-v2.patch,
#    (optionally) apply kernel/ambient-caps-3.18.patch, build Image.gz (GCC 4.9 aarch64).
# 2. DTB:  python3 scripts/patch_dtb.py <dtb> <out.dtb> --ramoops
# 3. Ramdisk: apply ramdisk/* (init.rc charger patch; init.qcom.rc, init.usb.rc, default.prop,
#    fstab.qcom as provided; real /default.prop file).
# 4. Sign:  scripts/make_signed_boot.sh  "Image.gz+dtb"  ramdisk.cpio.gz  boot.img  "<cmdline>"
#    cmdline: androidboot.hardware=qcom androidboot.bootdevice=7824900.sdhci (SELinux enforcing;
#    add androidboot.selinux=permissive only for debugging). The ramdisk needs the sepolicy and
#    *_contexts built from the tree (mka selinux_policy nonplat_property_contexts ...).
# 5. Flash userspace, keep stock boot on the partition, RAM-boot the signed image:
fastboot flash system system.img && fastboot flash vendor vendor.img
#    Re-flashing system over an existing install: afterwards run
#    adb shell cmd package compile --reset -a     (see fix 44 - stale JIT profiles)
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
#    /vendor/etc/init/android.hardware.sensors@1.0-service.rc with vendor/sensors/'s copy and move
#    unwanted rc files to /vendor/etc/init-disabled. Finally: adb shell restorecon -R /vendor
# For a reproducible build: apply device/device-tree.patch, add device/liblight and device/configs to the device tree,
# drop the lights blob and swap in the Oreo camera blobs (device/vendor-blobs.md), fold 11-15 into
# the vendor image, and apply 16.
```

## Remaining work (help wanted)
- **WiFi hotspot:** untested; `WCNSS_qcom_cfg_ags.ini` (the Huawei per-device variant) vs the generic
  `WCNSS_qcom_cfg.ini` currently used is worth comparing.
- **Bluetooth**, **GPS**: not brought up.
- Make all the on-device fixes part of the vendor/system image for a one-shot flash. `/vendor` on this unit still
  differs from a tree build: stock Oreo GPU/display/audio blobs, removed TrustZone `gatekeeper`/`keystore` modules,
  the generic light + GNSS stub HALs, Adreno firmware in `/vendor/firmware`, a hand-edited `build.prop`.

## Credits & license
Built on the GPLv2 Linux kernel and the clienthax and LineageOS sources; the ambient-caps patch is
upstream (Andy Lutomirski, v4.3); the Oreo camera driver comes from Huawei's GPL release as published
in [adeii/huawei-london-kernel](https://github.com/adeii/huawei-london-kernel) (commit d6d5b83). Shared in the same spirit — use at your own risk, no warranty.
Flashing firmware can brick your device.
