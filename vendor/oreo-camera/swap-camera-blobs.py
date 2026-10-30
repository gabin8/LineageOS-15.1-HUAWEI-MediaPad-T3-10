#!/usr/bin/env python3
"""Replace the Nougat (EMUI 5) camera blob set in the LineageOS vendor/device trees with the
stock EMUI 8.0 Oreo one (AGS-W09 C185 vendor.img), which matches the Oreo-era camera_v2 kernel.

usage: swap-camera-blobs.py <lineage source root> <mounted stock Oreo vendor.img>

  * deletes nougat-camera-remove.txt from proprietary/, ags_w09-vendor.mk, proprietary-files.txt
  * copies oreo-camera-add.txt from the Oreo vendor image and lists any new paths
  * installs cpp_firmware_*.fw to /vendor/firmware (ueventd never searches /vendor/etc/firmware)
Re-running is a no-op. Afterwards run patch-camera-blobs.sh on proprietary/vendor/lib.
"""
import os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
root, oreo = sys.argv[1], sys.argv[2]
VT = os.path.join(root, 'vendor/huawei/ags_w09')
PROP = os.path.join(VT, 'proprietary')
MK = os.path.join(VT, 'ags_w09-vendor.mk')
PFT = os.path.join(root, 'device/huawei/ags_w09/proprietary-files.txt')

def lst(name):
    return [l.strip() for l in open(os.path.join(HERE, name)) if l.strip()]

remove, add = set(lst('nougat-camera-remove.txt')), lst('oreo-camera-add.txt')

def mk_line(path, dest=None):
    return '    vendor/huawei/ags_w09/proprietary/%s:$(TARGET_COPY_OUT_VENDOR)/%s \\\n' % (
        path, (dest or path)[len('vendor/'):])

def pft_key(line):
    s = line.strip().lstrip('#').strip().lstrip('-')
    return s.split()[0].split(':')[0] if s else ''

# blobs
for p in remove:
    f = os.path.join(PROP, p)
    if os.path.exists(f):
        os.remove(f)
for p in add:
    d = os.path.join(PROP, p)
    os.makedirs(os.path.dirname(d), exist_ok=True)
    shutil.copy2(os.path.join(oreo, p[len('vendor/'):]), d)

# ags_w09-vendor.mk
mk = open(MK).read().splitlines(True)
src = lambda l: l.strip().split(':')[0].replace('vendor/huawei/ags_w09/proprietary/', '')
mk = [l for l in mk if not (l.startswith('    vendor/huawei/ags_w09/proprietary/') and src(l) in remove)]
have = {src(l) for l in mk if l.startswith('    vendor/huawei/ags_w09/proprietary/')}
start = next(i for i, l in enumerate(mk) if l.startswith('PRODUCT_COPY_FILES')) + 1
mk[start:start] = [mk_line(p) for p in add if p not in have]
for i, l in enumerate(mk):
    if '/etc/firmware/cpp_firmware_' in l:
        p = src(l)
        mk[i] = mk_line(p, p.replace('vendor/etc/firmware/', 'vendor/firmware/'))
open(MK, 'w').writelines(mk)

# proprietary-files.txt (kept sorted by path; comments stay where they are)
pf = [l for l in open(PFT).read().splitlines(True)
      if not (not l.startswith('#') and pft_key(l) in remove)]
have = {pft_key(l) for l in pf if not l.startswith('#')}
for p in add:
    if p in have:
        continue
    i = next((i for i, l in enumerate(pf) if pft_key(l) > p), len(pf))
    pf.insert(i, p + '\n')
for i, l in enumerate(pf):
    if l.startswith('vendor/etc/firmware/cpp_firmware_') and ':' not in l:
        p = l.strip()
        pf[i] = '%s:%s\n' % (p, p.replace('vendor/etc/firmware/', 'vendor/firmware/'))
open(PFT, 'w').writelines(pf)
print('removed %d, installed %d Oreo camera blobs' % (len(remove), len(add)))
