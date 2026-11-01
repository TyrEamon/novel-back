#!/usr/bin/env python3
"""Verify the zero-provider, one-ABI APK before release."""
from __future__ import annotations
import argparse
from pathlib import Path
from zipfile import ZipFile
import json

def has_source_rules(value):
    if isinstance(value, dict):
        if 'bookSourceUrl' in value and 'bookSourceName' in value:
            return True
        return any(has_source_rules(v) for v in value.values())
    return isinstance(value, list) and any(has_source_rules(v) for v in value)


def verify(apk: Path, abi: str):
    with ZipFile(apk) as archive:
        names = archive.namelist()
        libraries = [n for n in names if n.startswith('lib/') and n.endswith('.so')]
        if any(n.endswith('/libcpp.so') for n in libraries):
            raise ValueError('The retired built-in content runtime must not be bundled in 0.4')
        if not {f'lib/{abi}/libflutter.so', f'lib/{abi}/libapp.so'}.issubset(names):
            raise ValueError(f'Missing Flutter release libraries for {abi}')
        if any(n.split('/')[1] != abi for n in libraries):
            raise ValueError(f'Unexpected architecture in this {abi} one-ABI APK')
        for name in names:
            if name.endswith('.js'):
                script = archive.read(name)
                if b'bookSourceUrl' in script and b'bookSourceName' in script:
                    raise ValueError(f'Bundled JavaScript content sources are not allowed: {name}')
            if name.startswith('assets/') and name.endswith('.json'):
                try:
                    value = json.loads(archive.read(name))
                except (ValueError, UnicodeDecodeError):
                    continue
                if has_source_rules(value):
                    raise ValueError(f'Bundled content source rules are not allowed: {name}')
            if name.endswith('.dex') and b'Lorg/mewx/wenku8_flutter/SourceFixtureProbe;' in archive.read(name):
                raise ValueError('Device probe entry point must not be included in release APKs')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--abi', required=True, choices=['armeabi-v7a','arm64-v8a','x86_64'])
    args = parser.parse_args()
    verify(args.apk, args.abi)
    print(f'{args.abi}: one-ABI release verified; no retired provider, bundled JSON/JS sources or device probe.')


if __name__ == '__main__':
    main()
