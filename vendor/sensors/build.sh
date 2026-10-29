#!/bin/sh
# Builds lib64/ and lib/ libshim_procname.so with the LOS tree's GCC 4.9 prebuilts.
set -e
cd "$(dirname "$0")"
T=/home/kompukter/Documents/huawei_ags_w09/los_build/lineage/prebuilts/gcc/linux-x86
FLAGS="-O2 -fPIC -shared -nostdlib -Wl,-soname,libshim_procname.so -Wl,--hash-style=both -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now"
mkdir -p lib64 lib
$T/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-gcc $FLAGS -o lib64/libshim_procname.so shim_procname.c
$T/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-gcc -march=armv7-a -mthumb $FLAGS -o lib/libshim_procname.so shim_procname.c
$T/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-strip --strip-unneeded lib64/libshim_procname.so
$T/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-strip --strip-unneeded lib/libshim_procname.so
