#!/usr/bin/env python3
"""Report actual APK download bytes and expanded contents, without repacking it."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import zipfile


def analyze(path):
    groups = defaultdict(lambda: {'stored_bytes': 0, 'expanded_bytes': 0, 'entries': 0})
    entries = []
    with zipfile.ZipFile(path) as apk:
        for entry in apk.infolist():
            name = entry.filename
            if name.endswith('/'):
                continue
            if name.startswith('lib/'):
                group = 'native/' + name.split('/')[1]
            elif '/fonts/' in name or name.endswith(('.ttf', '.otf')):
                group = 'fonts'
            elif name.endswith('.dex'):
                group = 'android_code'
            elif name.startswith('assets/flutter_assets/'):
                group = 'flutter_assets'
            else:
                group = 'android_resources'
            row = {'name': name, 'stored_bytes': entry.compress_size,
                   'expanded_bytes': entry.file_size}
            entries.append(row)
            groups[group]['stored_bytes'] += entry.compress_size
            groups[group]['expanded_bytes'] += entry.file_size
            groups[group]['entries'] += 1
    stored = sum(e['stored_bytes'] for e in entries)
    return {'apk': str(path), 'apk_bytes': path.stat().st_size,
            'expanded_entry_bytes': sum(e['expanded_bytes'] for e in entries),
            'archive_overhead_bytes': path.stat().st_size - stored,
            'groups': dict(groups),
            'largest_entries': sorted(entries, key=lambda e: e['stored_bytes'], reverse=True)[:20]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--baseline', type=Path)
    args = parser.parse_args()
    report = analyze(args.apk)
    if args.baseline:
        before = analyze(args.baseline)['apk_bytes']
        report['comparison'] = {'baseline_bytes': before,
                                'delta_bytes': report['apk_bytes'] - before,
                                'reduction_percent': 100 * (before - report['apk_bytes']) / before}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f"APK {report['apk_bytes'] / 1_000_000:.2f} MB; expanded entries "
          f"{report['expanded_entry_bytes'] / 1_000_000:.2f} MB")
    if 'comparison' in report:
        print(f"Reduction: {report['comparison']['reduction_percent']:.2f}%")


if __name__ == '__main__':
    main()
