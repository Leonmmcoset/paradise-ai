import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../hook/rust_target.dart';

void main() {
  test('Apple device and simulator select distinct Rust ABIs', () {
    expect(rustTarget(OS.iOS, Architecture.arm64, iosSdk: IOSSdk.iPhoneOS), 'aarch64-apple-ios');
    expect(rustTarget(OS.iOS, Architecture.arm64, iosSdk: IOSSdk.iPhoneSimulator), 'aarch64-apple-ios-sim');
    expect(rustTarget(OS.iOS, Architecture.x64, iosSdk: IOSSdk.iPhoneSimulator), 'x86_64-apple-ios');
    expect(rustTarget(OS.iOS, Architecture.x64, iosSdk: IOSSdk.iPhoneOS), isNull);
    expect(rustTarget(OS.macOS, Architecture.arm64), 'aarch64-apple-darwin');
    expect(rustTarget(OS.macOS, Architecture.x64), 'x86_64-apple-darwin');
    expect(rustLibraryName(OS.iOS), 'liboii_bridge.dylib');
    expect(rustLibraryName(OS.macOS), 'liboii_bridge.dylib');
  });

  test('Android and Linux retain their existing targets and library names', () {
    expect(rustTarget(OS.android, Architecture.arm64), 'aarch64-linux-android');
    expect(rustTarget(OS.android, Architecture.arm), 'armv7-linux-androideabi');
    expect(rustTarget(OS.android, Architecture.x64), 'x86_64-linux-android');
    expect(rustTarget(OS.linux, Architecture.x64), 'x86_64-unknown-linux-gnu');
    expect(rustLibraryName(OS.android), 'liboii_bridge.so');
  });
}
