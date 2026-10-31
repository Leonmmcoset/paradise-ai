import 'package:flutter/foundation.dart';

// The PRoot runtime needs Android's process/ptrace support. File tools and
// managed workspaces are independent of it and remain available on iOS.
bool get supportsLocalEnvironment => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
