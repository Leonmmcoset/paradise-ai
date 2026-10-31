#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'iOS simulator tests require macOS and Xcode.' >&2
  exit 1
fi
# A supplied UDID lets a developer choose an existing simulator. CI chooses an
# available iPhone from the newest installed iOS runtime.
simulator=${1:-}
if [[ -z "$simulator" ]]; then
  simulator=$(python3 - <<'PY'
import json, re, subprocess
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
for runtime in sorted(devices, key=lambda r: tuple(map(int, re.findall(r'\d+', r))), reverse=True):
    if '.iOS-' not in runtime:
        continue
    for device in devices[runtime]:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            print(device['udid'])
            raise SystemExit(0)
raise SystemExit('No available iPhone simulator; install an iOS runtime in Xcode.')
PY
)
fi
xcrun simctl bootstatus "$simulator" -b
flutter test integration_test/ios_smoke_test.dart --device-id "$simulator" --timeout 5m --reporter expanded
