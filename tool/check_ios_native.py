#!/usr/bin/env python3
"""Fail early if an iOS FFI dependency has missing XCFramework slices."""
import json
from pathlib import Path
import plistlib
from urllib.parse import unquote, urljoin, urlparse

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = {('device', 'arm64'), ('simulator', 'arm64'), ('simulator', 'x86_64')}


def check_framework(framework):
    info = framework / 'Info.plist'
    if not info.is_file():
        raise ValueError(f'Missing {info}. Run dart run typst_flutter:setup --force.')
    covered = set()
    for library in plistlib.loads(info.read_bytes())['AvailableLibraries']:
        if library['SupportedPlatform'] != 'ios':
            continue
        binary = framework / library['LibraryIdentifier'] / library['LibraryPath']
        if not binary.is_file() or binary.stat().st_size == 0:
            raise ValueError(f'Missing native library: {binary}')
        variant = library.get('SupportedPlatformVariant', 'device')
        covered.update((variant, arch) for arch in library['SupportedArchitectures'])
    if missing := REQUIRED - covered:
        raise ValueError(f'{framework.name} lacks required iOS slices: {sorted(missing)}')
    print(f'{framework.name}: device arm64, simulator arm64/x86_64 present')


def main():
    config = ROOT / '.dart_tool/package_config.json'
    packages = {
        p['name']: Path(unquote(urlparse(urljoin(config.as_uri(), p['rootUri'])).path))
        for p in json.loads(config.read_text())['packages']
    }
    check_framework(packages['typst_flutter'] / '.typst_flutter_prebuilt/ios/typst_flutter.xcframework')
    check_framework(packages['ratex_flutter'] / 'ios/ratex_flutter/RaTeX.xcframework')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error)) from error
