#!/usr/bin/env python3
"""Render the existing Paradise mark for iOS (requires ImageMagick)."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from generate_launcher_icons import read_shape, fit

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'ios/Runner/Assets.xcassets'


def main():
    renderer = shutil.which('magick') or shutil.which('convert')
    if not renderer:
        raise SystemExit('Install ImageMagick to regenerate iOS icons.')
    with tempfile.TemporaryDirectory(prefix='paradise-ios-icons-') as scratch:
        source = Path(scratch) / 'source.svg'
        source.write_text((ROOT / 'assets/icon/icon.svg').read_text().replace('currentColor', '#000000'))
        geometry = subprocess.check_output([
            renderer, '-background', 'none', str(source), '-resize', '1000x1000',
            '-format', '%@', 'info:',
        ], text=True).strip()
        match = re.fullmatch(r'(\d+)x(\d+)\+(\d+)\+(\d+)', geometry)
        if not match:
            raise SystemExit(f'Could not measure the icon: {geometry}')
        w, h, x, y = map(int, match.groups())
        scale, tx, ty = fit((x / 10, y / 10, (x + w) / 10, (y + h) / 10), 40, 100)
        path, width, (cx, cy, radius) = read_shape()
        sheet = Path(scratch) / 'ios.svg'
        # iOS applies its own corner mask. Export opaque square RGB images.
        sheet.write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="1024" height="1024">
<rect width="100" height="100" fill="white"/>
<g transform="translate({tx} {ty}) scale({scale})">
<path d="{path}" fill="none" stroke="black" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>
<circle cx="{cx}" cy="{cy}" r="{radius}" fill="black"/>
</g></svg>''')

        def render(destination, pixels):
            subprocess.run([renderer, str(sheet), '-resize', f'{pixels}x{pixels}',
                            '-alpha', 'off', f'PNG24:{destination}'], check=True)

        catalog = ASSETS / 'AppIcon.appiconset'
        for item in json.loads((catalog / 'Contents.json').read_text())['images']:
            pixels = round(float(item['size'].split('x')[0]) * float(item['scale'][:-1]))
            render(catalog / item['filename'], pixels)
        for suffix, pixels in [('', 168), ('@2x', 336), ('@3x', 504)]:
            render(ASSETS / f'LaunchImage.imageset/LaunchImage{suffix}.png', pixels)
    print('Generated iPhone, iPad, App Store, and launch images from assets/icon/icon.svg.')


if __name__ == '__main__':
    main()
