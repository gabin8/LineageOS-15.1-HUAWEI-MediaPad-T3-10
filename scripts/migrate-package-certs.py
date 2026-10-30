#!/usr/bin/env python3
"""Rewrite /data/system/packages.xml so apps installed under the AOSP test keys keep working after the
system is re-signed with our release keys: replace each test certificate (DER hex in <cert key=...>)
with the matching release certificate. usage: migrate_certs.py <packages.xml in> <out> <lineage root>"""
import os, subprocess, sys
src, dst, root = sys.argv[1:4]
SEC = os.path.join(root, 'build/target/product/security')
NEW = os.path.expanduser('~/.android-certs')
def der_hex(pem):
    return subprocess.run(['openssl', 'x509', '-in', pem, '-outform', 'DER'],
                          capture_output=True, check=True).stdout.hex()
pairs = [('testkey', 'releasekey'), ('platform', 'platform'), ('shared', 'shared'), ('media', 'media')]
xml = open(src).read()
for old, new in pairs:
    o, n = der_hex(f'{SEC}/{old}.x509.pem'), der_hex(f'{NEW}/{new}.x509.pem')
    count = xml.count(f'key="{o}"')
    if count != 1:
        sys.exit(f'{old}: expected exactly one cert definition, found {count}')
    xml = xml.replace(f'key="{o}"', f'key="{n}"')
    print(f'{old} -> {new}: replaced')
open(dst, 'w').write(xml)
