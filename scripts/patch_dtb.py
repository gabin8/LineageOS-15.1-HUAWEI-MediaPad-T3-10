#!/usr/bin/env python3
# Patch the AGS-W09 DTB so the engineering QRD aboot selects it, and (optionally) add
# a ramoops/pstore region for crash capture.
#   usage: patch_dtb.py <in.dtb> <out.dtb> [--ramoops]
# Requires: dtc in PATH.
import sys, subprocess, tempfile, os, re
inp, outp = sys.argv[1], sys.argv[2]
ramoops = '--ramoops' in sys.argv[3:]
dts = subprocess.check_output(['dtc','-I','dtb','-O','dts', inp], stderr=subprocess.DEVNULL).decode('latin1')
# 1) board-id 0x1f55 (retail) -> 0x1000b (what the eng QRD aboot reports: QRD SKU5)
dts = re.sub(r'(qcom,board-id = <)0x1f55( 0x0?0?>)', r'\g<1>0x1000b\g<2>', dts)
if 'android,fstab' not in dts and ramoops:
    def ins(text, anchor, child):
        i = text.index(anchor) + len(anchor); depth = 1; j = i
        while depth > 0:
            c = text[j]; depth += (c=='{') - (c=='}'); j += 1
        close = text.rfind('\n', 0, j-1)
        return text[:close+1] + child + text[close+1:]
    dts = ins(dts, '\treserved-memory {\n',
        '\t\tram_oops_mem@9f000000 {\n\t\t\tcompatible = "ramoops_mem";\n\t\t\tno-map;\n\t\t\treg = <0x0 0x9f000000 0x0 0x200000>;\n\t\t};\n')
    dts = ins(dts, '\n\tsoc {\n',
        '\t\tram_oops {\n\t\t\tcompatible = "ramoops";\n\t\t\tandroid,ramoops-buffer-start = <0x9f000000>;\n\t\t\tandroid,ramoops-buffer-size = <0x200000>;\n\t\t\tandroid,ramoops-console-size = <0x100000>;\n\t\t\tandroid,ramoops-record-size = <0x20000>;\n\t\t\tandroid,ramoops-pmsg-size = <0x80000>;\n\t\t\tandroid,ramoops-dump-oops = <0x1>;\n\t\t};\n')
with tempfile.NamedTemporaryFile('w', suffix='.dts', delete=False) as tf:
    tf.write(dts); tfp = tf.name
subprocess.check_call(['dtc','-I','dts','-O','dtb','-o', outp, tfp], stderr=subprocess.DEVNULL)
os.unlink(tfp)
print("patched DTB ->", outp, "(ramoops)" if ramoops else "")
