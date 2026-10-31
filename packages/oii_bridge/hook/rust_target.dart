import 'package:code_assets/code_assets.dart';

/// Device and simulator ARM64 have different ABIs despite sharing a CPU.
String? rustTarget(OS os, Architecture arch, {IOSSdk? iosSdk}) {
  if (os == OS.iOS) {
    if (iosSdk == IOSSdk.iPhoneOS) {
      return arch == Architecture.arm64 ? 'aarch64-apple-ios' : null;
    }
    if (iosSdk == IOSSdk.iPhoneSimulator) {
      return switch (arch) {
        Architecture.arm64 => 'aarch64-apple-ios-sim',
        Architecture.x64 => 'x86_64-apple-ios',
        _ => null,
      };
    }
    return null;
  }
  if (os == OS.macOS) {
    return switch (arch) {
      Architecture.arm64 => 'aarch64-apple-darwin',
      Architecture.x64 => 'x86_64-apple-darwin',
      _ => null,
    };
  }
  if (os == OS.android) {
    return switch (arch) {
      Architecture.arm64 => 'aarch64-linux-android',
      Architecture.arm => 'armv7-linux-androideabi',
      Architecture.x64 => 'x86_64-linux-android',
      _ => null,
    };
  }
  if (os == OS.linux) {
    return switch (arch) {
      Architecture.arm64 => 'aarch64-unknown-linux-gnu',
      Architecture.x64 => 'x86_64-unknown-linux-gnu',
      _ => null,
    };
  }
  return null;
}

String rustLibraryName(OS os) =>
    os == OS.iOS || os == OS.macOS ? 'liboii_bridge.dylib' : 'liboii_bridge.so';
