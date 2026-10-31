import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paradise/data/local_files.dart';
import 'package:paradise/data/models.dart';
import 'package:paradise/data/human/sticker_lib.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'fake_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => LocalFiles.documentsRoot = null);

  test('saved iOS media follows a moved data container', () {
    const old = '/var/mobile/Containers/Data/Application/OLD/Documents';
    const current = '/var/mobile/Containers/Data/Application/NEW/Documents';
    LocalFiles.documentsRoot = current;
    final msg = Msg.fromJson({
      'id': 'm', 'out': true, 'text': '', 'time': 1, 'kind': 'photo',
      'data': {'path': '$old/attachments/a.jpg', 'thumb': '/private$old/attachments/thumb.jpg'},
    });
    expect(msg.data['path'], '$current/attachments/a.jpg');
    expect(msg.data['thumb'], '$current/attachments/thumb.jpg');
    expect(UserPersona.fromJson({'avatarPath': '$old/avatars/a.jpg'}).avatarPath, '$current/avatars/a.jpg');
    expect(UserSticker.fromJson({'id': 's', 'value': '$old/stickers/a.gif'}).value, '$current/stickers/a.gif');
    expect(LocalFiles.resolve('/Users/u/Library/Developer/CoreSimulator/Devices/D/data/Containers/Data/Application/A/Documents/wallpapers/a.jpg'), '$current/wallpapers/a.jpg');
  });

  test('URLs, Android paths, arbitrary directories and traversal stay untouched', () {
    LocalFiles.documentsRoot = '/current/Documents';
    for (final path in [
      'https://example.com/Documents/a.jpg', '/data/user/0/fan.x0.para/a.jpg',
      '/someone/Documents/a.jpg',
      '/var/mobile/Containers/Data/Application/OLD/Documents/../Library/a.jpg',
    ]) {
      expect(LocalFiles.resolve(path), path);
    }
  });

  test('a kept picker file survives deletion of its cached original', () async {
    final root = await Directory.systemTemp.createTemp('kept_media');
    final previous = PathProviderPlatform.instance;
    addTearDown(() async {
      PathProviderPlatform.instance = previous;
      await root.delete(recursive: true);
    });
    final docs = Directory('${root.path}/Documents')..createSync();
    PathProviderPlatform.instance = FakePathProvider(docs.path);
    final picked = File('${root.path}/picked.png');
    await picked.writeAsBytes([1, 2, 3]);
    final kept = await LocalFiles.keep(picked.path, 'avatars');
    await picked.delete();
    expect(await File(kept).readAsBytes(), [1, 2, 3]);
    expect(await LocalFiles.keep(kept, 'avatars'), kept);
  });
}
