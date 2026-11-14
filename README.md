# LineageOS 15.1 for HUAWEI MediaPad T3 10 (AGS-W09)

Unofficial LineageOS 15.1 (Android 8.1) for the Wi-Fi MediaPad T3 10: model **AGS-W09**,
Snapdragon 425 (MSM8917), 2 GB RAM, codename **agassi**.

For Android 10, with Bluetooth, GPS and hotspot, see the
[LineageOS 17.1 port](https://github.com/gabin8/LineageOS-17.1-HUAWEI-MediaPad-T3-10).

> ⚠️ **AGS-W09 (MediaPad T3, Snapdragon) is not AGS2-W09 (MediaPad T5, Kirin).** Never cross-flash.

## Download
[v15.1-20261102](https://github.com/gabin8/LineageOS-15.1-HUAWEI-MediaPad-T3-10/releases/tag/v15.1-20261102)
(test build): boot, system, vendor and product images plus `INSTALL.txt`. Read `INSTALL.txt` first.

- Needs the engineering bootloader.
- The boot image is **RAM-booted only**: `fastboot boot <image>`. Never `fastboot flash boot`;
  that drops the tablet into Qualcomm download mode (`05c6:900e`, black screen).
- After every power-off or restart, boot it again from a PC.

## Status
**Works:** Wi-Fi (2.4 and 5 GHz), audio, both cameras, hardware video decoding, accelerometer and
auto-rotate, touch, charging, WebView, LiveDisplay adaptive backlight, SELinux enforcing, release-key
signed.

**Not working:**
- No booting without a PC (see above).
- Bluetooth and GPS are not brought up.
- Wi-Fi hotspot is untested.

## Source
| Path | Contents |
|---|---|
| [`kernel/`](kernel/) | Patches and the binder backport for clienthax's 3.18 kernel |
| [`device/`](device/) | Device tree patch, light HAL, shims, SELinux policy, blob notes |
| [`frameworks/`](frameworks/) | Patches to LineageOS 15.1 sources |
| [`ramdisk/`](ramdisk/) | Boot ramdisk files |
| [`vendor/`](vendor/) | Scripts and files that adapt the stock EMUI 8 vendor partition |
| [`scripts/`](scripts/) | Boot image signing, DTB patching and build signing tools |
| [`docs/`](docs/) | Detailed [porting notes](docs/lineage-15.1-notes.md): the full fix chain and build outline |

## Credits
clienthax (kernel and device tree), the LineageOS project, Huawei's GPL camera driver via
[adeii/huawei-london-kernel](https://github.com/adeii/huawei-london-kernel), and the upstream
ambient-capabilities patch (Andy Lutomirski).

Use at your own risk, no warranty. Flashing firmware can brick your device.
