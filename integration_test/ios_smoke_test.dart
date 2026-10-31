import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as contacts;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:oii_bridge/oii_bridge.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:ratex_flutter/ratex_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typst_flutter/typst_flutter.dart' as typst;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'package:paradise/data/ai_config.dart';
import 'package:paradise/data/db.dart';
import 'package:paradise/data/human/notifications.dart';
import 'package:paradise/data/local_files.dart';
import 'package:paradise/data/models.dart';
import 'package:paradise/data/store.dart';
import 'package:paradise/main.dart';
import 'package:paradise/ui/canvas_cards.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS starts with storage, backups, and workspace file tools', (tester) async {
    expect(Platform.isIOS, isTrue);
    late Store store;
    late AiConfig ai;
    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ios.smoke', 'persisted');
      await prefs.reload();
      expect(prefs.getString('ios.smoke'), 'persisted');
      await prefs.remove('ios.smoke');

      final docs = await getApplicationDocumentsDirectory();
      final support = await getApplicationSupportDirectory();
      expect(await docs.exists(), isTrue);
      expect(await support.exists(), isTrue);
      final db = await ChatDb.open(path: '${docs.path}/ios-smoke.db');
      try {
        final chat = Chat(id: 'native', persona: Persona(name: 'iOS', prompt: 'test', color: 0));
        chat.msgs.add(Msg(id: 'm', out: true, text: 'saved on iOS', time: 1));
        await db.saveChat(chat, 0, msgs: chat.msgs);
        expect((await db.loadChats()).single.id, 'native');
        expect((await db.loadMsgs('native')).single.text, 'saved on iOS');
      } finally {
        await db.close();
      }

      store = await Store.load();
      ai = await AiConfig.load();
      store.attachAi(ai);
      await bootStore(store);
      expect(store.wsAvailable('read_file'), isTrue);
      expect(store.wsAvailable('shell'), isFalse);
      expect(await store.exportBackupArchive(), isNotEmpty);

      final cached = File('${(await getTemporaryDirectory()).path}/picked.txt');
      await cached.writeAsString('keep me');
      final kept = await LocalFiles.keep(cached.path, 'attachments');
      await cached.delete();
      expect(await File(kept).readAsString(), 'keep me');
      await File(kept).delete();
    });
    addTearDown(() => store.shutdownForReplace());
    await tester.pumpWidget(TgApp(store: store, ai: ai));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('permission, notification, TTS, and background plugins register', (tester) async {
    await tester.runAsync(() async {
      // Status reads exercise registration without showing permission dialogs.
      await Permission.notification.status;
      await PhotoManager.getPermissionState(requestOption: const PermissionRequestOption());
      await Geolocator.checkPermission();
      await contacts.FlutterContacts.permissions.check(contacts.PermissionType.read);
      expect(await FlutterTts().getVoices, isA<List>());

      final notifications = FlutterLocalNotificationsPlugin();
      expect(await notifications.initialize(notificationSettings), isTrue);
      expect(await notifications.pendingNotificationRequests(), isA<List<PendingNotificationRequest>>());
      await Workmanager().initialize(backgroundDispatcher);
    });
  });

  testWidgets('OII FFI, isolates, and native math execute on Apple', (tester) async {
    await tester.runAsync(() async {
      final engine = await OiiEngine.spawn();
      try {
        engine.registerHost('double', (args) => (args.first as num) * 2);
        final parsed = await engine.parse('fun main() [ return double(21) ]');
        expect(parsed.ok, isTrue, reason: parsed.diagnostics.join('\n'));
        final result = await engine.eval('main');
        expect(result.ok, isTrue, reason: result.error);
        expect(result.value, 42);
        expect(oiiValidateBackupDoc('chat [ id: "ios" ]').ok, isTrue);
      } finally {
        engine.dispose();
      }
      final math = RaTeXEngine.instance.parseAndLayout(r'\frac{1}{2} + x^2');
      expect(math.width, greaterThan(0));
      expect(math.items, isNotEmpty);
    });
  });

  testWidgets('Typst renders bundled CeTZ and CJK fonts without a network', (tester) async {
    await tester.runAsync(() async {
      final compiler = await typst.TypstCompiler.create(
        fonts: const typst.FontSource.assets(['assets/fonts/wqy-microhei.ttc']),
      );
      try {
        final packages = await TypstPackageStore.ensure();
        expect(packages, isNotEmpty);
        final doc = await compiler.compile(
          source: wrapCetz('''#cetz.canvas({
            import cetz.draw: *
            circle((0, 0), radius: 1)
            content((0, 0), [你好 iOS])
          })''', dark: false),
          files: typst.FileSource.bytes(packages),
          allowPackages: false,
        );
        try {
          expect(doc.pageCount, 1);
          expect(await doc.renderSvg(0), contains('<svg'));
        } finally {
          doc.dispose();
        }
      } finally {
        compiler.dispose();
      }
    });
  });

  testWidgets('WKWebView displays a document and executes JavaScript', (tester) async {
    final loaded = Completer<void>();
    final controller = WebViewController();
    await tester.runAsync(() async {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
        if (!loaded.isCompleted) loaded.complete();
      }));
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WebViewWidget(controller: controller))));
    await tester.runAsync(() async {
      await controller.loadHtmlString('<html><body>ios-ok</body></html>');
      await loaded.future.timeout(const Duration(seconds: 30));
      expect(await controller.runJavaScriptReturningResult('document.body.textContent'), contains('ios-ok'));
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('AVFoundation audio decodes a local speech file', (tester) async {
    await tester.runAsync(() async {
      final file = File('${(await getTemporaryDirectory()).path}/ios-smoke.wav');
      // 100 ms of mono PCM silence at 8 kHz, a real decoder input.
      final wav = ByteData(44 + 1600);
      void tag(int offset, String text) {
        for (var i = 0; i < text.length; i++) wav.setUint8(offset + i, text.codeUnitAt(i));
      }
      tag(0, 'RIFF'); tag(8, 'WAVE'); tag(12, 'fmt '); tag(36, 'data');
      wav.setUint32(4, wav.lengthInBytes - 8, Endian.little);
      wav.setUint32(16, 16, Endian.little);
      wav.setUint16(20, 1, Endian.little);
      wav.setUint16(22, 1, Endian.little);
      wav.setUint32(24, 8000, Endian.little);
      wav.setUint32(28, 16000, Endian.little);
      wav.setUint16(32, 2, Endian.little);
      wav.setUint16(34, 16, Endian.little);
      wav.setUint32(40, 1600, Endian.little);
      await file.writeAsBytes(wav.buffer.asUint8List());
      final player = AudioPlayer();
      try {
        expect(await player.setFilePath(file.path), isNotNull);
      } finally {
        await player.dispose();
        await file.delete();
      }
    });
  });
}
