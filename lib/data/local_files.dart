import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// iOS can move the data container when an app is updated or restored. Resolve
/// saved document paths against this launch's container before reading them.
class LocalFiles {
  static String? documentsRoot;

  static Future<void> initialize() async {
    if (Platform.isIOS) documentsRoot = (await getApplicationDocumentsDirectory()).path;
  }

  static final _device = RegExp(r'^/(?:private/)?var/mobile/Containers/Data/Application/[^/]+/Documents/(.+)$');
  static final _simulator = RegExp(r'^/.*/CoreSimulator/Devices/[^/]+/data/Containers/Data/Application/[^/]+/Documents/(.+)$');

  static String resolve(String path) {
    final root = documentsRoot;
    if (root == null || path.isEmpty) return path;
    final relative = (_device.firstMatch(path) ?? _simulator.firstMatch(path))?.group(1);
    if (relative == null || p.posix.isAbsolute(relative) || relative.split('/').contains('..')) return path;
    return p.join(root, relative);
  }

  /// Picker results and photo_manager exports live in caches. Own a copy
  /// before saving a reference so deleting a gallery item or purging a cache
  /// cannot erase a sent attachment or avatar.
  static Future<String> keep(String path, String folder) async {
    final source = resolve(path);
    final docs = (await getApplicationDocumentsDirectory()).path;
    if (p.isWithin(docs, source)) return source;
    final dir = Directory(p.join(docs, folder));
    await dir.create(recursive: true);
    final dest = File(p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}_${p.basename(source)}'));
    try {
      await File(source).copy(dest.path);
      return dest.path;
    } catch (_) {
      if (await dest.exists()) await dest.delete();
      rethrow;
    }
  }
}
