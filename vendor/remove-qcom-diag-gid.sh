#!/bin/sh
# ★ THE primary boot blocker fix ★
# The vendor permission XMLs map a permission to gid="qcom_diag", but qcom_diag is NOT in the
# bionic AID table this ROM was built with (device/.../config.fs defines AID_QCOM_DIAG 2950, but
# Android 8.1 bionic does not read /system/etc/group). So Process.getGidForName("qcom_diag") == -1,
# and every app under a *system* shared-uid that holds such a permission (android.uid.system:
# Settings/FallbackHome; android.uid.phone: com.android.phone) is launched with a -1 supplementary
# gid -> the kernel rejects setgroups() with EINVAL -> the zygote child aborts silently (SIGABRT,
# no logcat, no tombstone because crash_dump also fails on this 3.18 kernel). App-uid procs carry
# no such gid, so they run fine -- which is why SystemUI came up but the HOME/setup-wizard never did.
# Fix: drop the qcom_diag <group> lines. SystemConfig re-reads these XMLs every boot.
# Permanent fix: do the same sed on vendor/huawei/ags_w09/proprietary/.../permissions/*.xml before
# building vendor.img (or add AID_QCOM_DIAG to a TARGET_FS_CONFIG_GEN config.fs that bionic reads).
set -e
for f in qti_permissions.xml qcom_logkit.xml com.qualcomm.location.xml; do
  [ -f /vendor/etc/permissions/$f ] && sed -i '/qcom_diag/d' /vendor/etc/permissions/$f
done
echo "qcom_diag gid removed"
