import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paradise/data/human/notifications.dart';
import 'package:paradise/data/store.dart';
import 'package:paradise/data/workspace/workspace.dart';
import 'package:paradise/data/workspace/workspace_bootstrap.dart';
import 'package:paradise/data/workspace/workspace_runtime.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    workspaceRuntimeProvider.debugSetStatus(null);
  });

  test('iOS starts without PRoot channels and can read and write workspace files', () async {
    final root = await Directory.systemTemp.createTemp('ios_workspace');
    final previous = PathProviderPlatform.instance;
    addTearDown(() async {
      PathProviderPlatform.instance = previous;
      await root.delete(recursive: true);
    });
    PathProviderPlatform.instance = FakePathProvider(root.path);
    SharedPreferences.setMockInitialValues({});
    final nativeCalls = <String>[];
    for (final name in ['app.workspace', 'app.workspace/events']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name), (call) async {
          nativeCalls.add(call.method);
          throw MissingPluginException();
        },
      );
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), null));
    }
    final stack = await bootstrapWorkspace();
    watchExtractEvents(stack.channel);
    expect((await stack.channel.probe()).ready, isFalse);
    expect(nativeCalls, isEmpty);

    final store = await Store.load();
    addTearDown(store.shutdownForReplace);
    final workspace = await store.workspace.create(name: 'iOS files');
    store.workspace.setToolsEnabled(true);
    final chat = store.createChat('iOS', 'test')..ws = WorkspaceBinding(workspaceId: workspace.id);
    // Even a restored/cached ready status must not expose Android tools on iOS.
    workspaceRuntimeProvider.debugSetStatus(const RuntimeStatus(ready: true));
    final tools = await store.wsTools(chat);
    expect(tools.map((t) => t.name), unorderedEquals(['read_file', 'write_file', 'edit_file', 'list_dir', 'glob', 'grep']));
    expect(store.wsAvailable('shell'), isFalse);
    expect(store.wsSummary(chat), contains('6/6'));
    await tools.firstWhere((t) => t.name == 'write_file').run({'path': '/workspace/note.txt', 'content': 'works on iOS'});
    expect(await tools.firstWhere((t) => t.name == 'read_file').run({'path': '/workspace/note.txt'}), contains('works on iOS'));
  });

  test('iOS notifications initialize quietly and use Darwin delivery settings', () async {
    IOSFlutterLocalNotificationsPlugin.registerWith();
    final calls = <MethodCall>[];
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final notifier = Notifier.instance;
    await notifier.init();
    final settings = calls.singleWhere((c) => c.method == 'initialize').arguments as Map;
    expect(settings['requestAlertPermission'], isFalse);
    expect(settings['requestBadgePermission'], isFalse);
    expect(settings['requestSoundPermission'], isFalse);
    await notifier.show('ios', 'Title', 'Message');
    final delivery = calls.singleWhere((c) => c.method == 'show').arguments as Map;
    expect(delivery['platformSpecifics'], contains('threadIdentifier'));
    expect(await notifier.requestPermission(), isTrue);
    expect(calls.any((c) => c.method == 'requestPermissions'), isTrue);
  });
}
