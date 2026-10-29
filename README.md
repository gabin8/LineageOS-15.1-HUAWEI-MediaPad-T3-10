# LineageOS 15.1 for Huawei MediaPad T3 10 (AGS-W09 / "agassi")

**Status: BOOTS END-TO-END to the LineageOS setup wizard / launcher.** system_server is stable,
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
| **Display panel** (BOE NT51017 9.6" 800p via lcdkit) + HWComposer/SurfaceFlinger | ✅ |
| **Live adb in the main boot** (FunctionFS gadget) | ✅ |
| **Full boot:** zygote → SystemUI → setup wizard / Trebuchet launcher | ✅ |
| Touch, power/volume keys (keylayout) | ✅ |
| Audio | ⚠️ silent **stub** — no ALSA card (ADSP/Q6 never inits; needs kernel work) |
| WiFi | ❌ prima module disabled during build (TODO) |
| GPS / real IZAT location | ❌ gnss is a stub HAL; QC location stack disabled (incompatible libs) |
| Cellular | n/a (Wi‑Fi-only SKU) |

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
13. **`audio_policy_configuration.xml`** — output-only **stub** audio policy (module `primary`,
    `AUDIO_DEVICE_OUT_STUB`, no input/r_submix) + disable `audio.primary.msm8937.so` so the stub
    `audio.primary.default.so` loads. There is **no ALSA sound card** (ADSP down); the real HAL and even
    an input stream crash audioserver. This gives silent audio so AudioService doesn't hang. (Also need
    the built `consumerir.default.so` and the `gnss@1.0` service on `/vendor` so IConsumerIr/IGnss register
    — system_server hard-blocks on them in this non-Treble build.)
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
adb shell 'mv /vendor/lib64/hw/audio.primary.msm8937.so /vendor/lib64/hw/audio.primary.msm8937.so.nocard; \
           mv /vendor/lib/hw/audio.primary.msm8937.so   /vendor/lib/hw/audio.primary.msm8937.so.nocard'
adb push vendor/remove-qcom-diag-gid.sh vendor/disable-incompatible-qc-apps.sh /data/local/tmp/
adb shell 'sh /data/local/tmp/remove-qcom-diag-gid.sh; sh /data/local/tmp/disable-incompatible-qc-apps.sh'
#    (and: consumerir.default.so + android.hardware.gnss@1.0-service/-impl + the generic light service,
#     all built from AOSP; see fixes 10 & 13.)
# For a reproducible build, fold 11/12/13/14/15 into the vendor image + PRODUCT_PACKAGES and apply 16.
```

## Remaining work (help wanted)
- **Audio:** real sound needs the Q6/ADSP (LPASS) to initialize so an ALSA card registers — a kernel
  bring-up effort (currently `snd_soc_register_card -517`, no `/proc/asound/cards`).
- **WiFi:** re-enable the prima WLAN module (disabled to get the ROM to build).
- Make all the on-device fixes part of the vendor/system image for a one-shot flash.

## Credits & license
Built on the GPLv2 Linux kernel and the clienthax and LineageOS sources; the ambient-caps patch is
upstream (Andy Lutomirski, v4.3). Shared in the same spirit — use at your own risk, no warranty.
Flashing firmware can brick your device.
