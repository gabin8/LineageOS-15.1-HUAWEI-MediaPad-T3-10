#!/system/bin/sh
# /init.wifi_mac.sh -- print this unit's factory WiFi MAC (XX:XX:XX:XX:XX:XX).
# Source: oeminfo record id 0x34, exactly as stock hw_wifi_get_mac() reads it
# (EMUI vendor libhardware_legacy.so / lib_hw_wifi_chipset_qcom.so):
# rmt_oeminfo_read(0x34, 256) -> RSA-2048 public decrypt (PKCS#1 v1.5 type 1,
# e=65537, Huawei key "publicKey_8f04") -> 12-byte plaintext; MAC = pt[5..0]
# (stored byte-reversed).
# oeminfo layout: 4K slot per id at (id-1)*0x1000 in bank A (0) or bank B
# (0x2000000); header "OEM_INFO", u32 ver=6, id, type, len, age; payload at +0x200.
# The RSA step takes ~40 s in awk, so the result is cached keyed by the record's
# sha256; later boots are instant. Prints nothing / exits 1 on any failure.
# NB: LOS 15.1 /system/bin/awk (20121220) has a broken opcode table: substr(),
# function return, unary minus and '!' crash or misbehave. The awk below uses
# none of them -- keep it that way when editing.
OI=${1:-/dev/block/platform/soc/7824900.sdhci/by-name/oeminfo}
CACHE=${2:-/data/misc/wifi/oeminfo_wifimac}
best=; bestage=-1
for blk in 51 8243; do
    h=$(dd if=$OI bs=4096 skip=$blk count=1 2>/dev/null | od -An -tx1 -v -N28 | tr -d ' \n')
    case $h in 4f454d5f494e464f06000000340000000100000000010000*) ;; *) continue ;; esac
    a=${h#????????????????????????????????????????????????}
    age=$((0x${a%??????}))
    [ $age -gt $bestage ] && { best=$blk; bestage=$age; }
done
[ -n "$best" ] || exit 1
key=$(dd if=$OI bs=4096 skip=$best count=1 2>/dev/null | sha256sum)
key=${key%% *}
if [ -r $CACHE ]; then
    read ckey cmac < $CACHE
    [ "$ckey" = "$key" ] && [ -n "$cmac" ] && { echo $cmac; exit 0; }
fi
mac=$(dd if=$OI bs=4096 skip=$best count=1 2>/dev/null | od -An -tu1 -v -j 512 -N 256 | awk '
function mont(a, b, r,  t, i, j, s, C, m, d) {
    for (j = 0; j <= L + 1; j++) t[j] = 0
    for (i = 0; i < L; i++) {
        C = 0
        for (j = 0; j < L; j++) { s = t[j] + a[j] * b[i] + C; C = int(s / B); t[j] = s - C * B }
        s = t[L] + C; C = int(s / B); t[L] = s - C * B; t[L + 1] = C
        m = (t[0] * NP) % B
        s = t[0] + m * n[0]; C = int(s / B)
        for (j = 1; j < L; j++) { s = t[j] + m * n[j] + C; C = int(s / B); t[j - 1] = s - C * B }
        s = t[L] + C; C = int(s / B); t[L - 1] = s - C * B; t[L] = t[L + 1] + C
    }
    d = 0
    for (j = L - 1; j >= 0; j--) { if (d == 0) { if (t[j] > n[j]) d = 1; if (t[j] < n[j]) d = 2 } }
    if (t[L] > 0) d = 1
    if (d < 2) {
        C = 0
        for (j = 0; j < L; j++) { s = t[j] - n[j] - C; C = 0; if (s < 0) { s += B; C = 1 }; t[j] = s }
    }
    for (j = 0; j < L; j++) r[j] = t[j]
}
BEGIN { L = 128; B = 65536; NP = 40955
    split("27853 62945 51380 52678 11667 57667 64276 3242 55227 7889 38274 52888 51519 27686 53998 39780 46781 20587 2178 57444 43099 26818 11800 17357 64223 55199 53209 57435 57436 47853 53567 50862 15892 2696 35333 26893 13869 36259 58850 9107 3979 55651 62941 60733 54171 7713 57009 31576 16804 16277 58317 32173 53138 10891 12836 31086 48773 41306 41540 54647 43074 30437 26047 8115 11623 12595 59457 37096 28423 2041 57299 18837 57731 59271 31183 50624 50548 25116 53762 50335 64306 41141 30379 13928 60570 34128 8810 382 36936 63192 44572 32423 63303 58723 54113 4298 42068 44526 19439 34368 55108 13616 31945 16273 24356 33665 40573 51675 32592 30803 26367 55667 14919 35102 32020 40620 40973 16343 59986 1373 16943 18595 56617 64037 39784 34954 35771 39741", tmp, " "); for (i = 0; i < L; i++) n[i] = tmp[i + 1] + 0
    split("15008 59915 35601 19093 30944 13321 55480 42824 42379 35270 40816 19363 31084 28023 10194 62876 26471 45782 62797 2442 47382 40980 2016 33276 63096 923 23148 52902 39456 36623 53100 1959 20713 59181 25184 30011 2529 30770 59178 33561 32803 51926 57019 54765 54444 35851 22450 13376 22039 48416 11561 45751 33850 29973 16344 18786 20710 5890 58312 1990 52025 25651 17346 52287 38669 29097 48045 52420 23520 4943 23116 42457 54023 40057 6308 23403 12799 16951 4605 51895 11798 50421 50264 15937 31951 23788 36656 27138 28401 60090 64469 38701 3701 22187 25836 51873 23781 4817 40637 47836 63184 46410 47010 48202 63699 59732 51642 59210 24503 5656 10802 19222 33739 929 9317 6148 28387 26294 9527 55437 30225 15382 57386 24960 43298 45409 20309 7607", tmp, " "); for (i = 0; i < L; i++) r2[i] = tmp[i + 1] + 0 }
{ for (i = 1; i <= NF; i++) by[nb++] = $i + 0 }
END {
    if (nb != 256) exit 1
    for (i = 0; i < L; i++) c[i] = by[254 - 2 * i] * 256 + by[255 - 2 * i]
    mont(c, r2, cm); for (i = 0; i < L; i++) x[i] = cm[i]
    for (k = 0; k < 16; k++) { mont(x, x, y); for (i = 0; i < L; i++) x[i] = y[i] }
    mont(x, cm, y); one[0] = 1; for (i = 1; i < L; i++) one[i] = 0; mont(y, one, p)
    bad = (p[127] != 1 || p[6] != 65280)
    for (i = 7; i < 127; i++) { if (p[i] != 65535) bad = 1 }
    if (bad) exit 1
    printf "%02X:%02X:%02X:%02X:%02X:%02X\n", p[3] % 256, int(p[3] / 256), p[4] % 256, int(p[4] / 256), p[5] % 256, int(p[5] / 256)
}')
case $mac in
    [0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]) ;;
    *) exit 1 ;;
esac
echo "$key $mac" > $CACHE.tmp && mv $CACHE.tmp $CACHE
echo $mac
