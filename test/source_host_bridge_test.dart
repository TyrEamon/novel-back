import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_host_bridge.dart';
import 'package:wenku8_flutter/sources/source_platform.dart';
import 'support/visual_review.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryState state;
  late Uint8List image;
  setUpAll(() async {
    await loadReviewFonts();
    image = await File('test/fixtures/source-captcha.png').readAsBytes();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = await LibraryState.load();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  Future<dynamic> native(String method, Map<String, dynamic> data) {
    const codec = StandardMethodCodec();
    final result = Completer<dynamic>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      SourcePlatform.channel.name,
      codec.encodeMethodCall(MethodCall(method, data)),
      (reply) {
        try {
          result.complete(reply == null ? null : codec.decodeEnvelope(reply));
        } catch (error, stack) {
          result.completeError(error, stack);
        }
      },
    );
    return result.future;
  }

  Future<SourceHostBridge> app(
    WidgetTester tester, {
    GlobalKey? capture,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = SourceHostBridge(state)..attach();
    addTearDown(host.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          navigatorKey: host.navigatorKey,
          navigatorObservers: [host],
          theme: novelTheme(Brightness.light, fontFamily: 'Roboto'),
          home: const Scaffold(body: Center(child: Text('书源验证'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return host;
  }

  testWidgets(
    'captcha uses shared glass sheet and submits its value without overlap',
    (tester) async {
      final capture = GlobalKey();
      await app(tester, capture: capture);
      final result = native('captcha', {
        'id': 'one',
        'source': '自编测试书源',
        'image': image,
      });
      await tester.pumpAndSettle();
      expect(find.byType(SourceCaptchaInput), findsOneWidget);
      final prompt = tester.widget<SourceCaptchaInput>(
        find.byType(SourceCaptchaInput),
      );
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(prompt.image),
          tester.element(find.byType(SourceCaptchaInput)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await captureReview(tester, capture, 'source-captcha-light');
      await tester.enterText(find.byType(TextField), '6B8K');
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(await result, '6B8K');
      expect(find.byType(SourceCaptchaInput), findsNothing);
    },
  );
  testWidgets(
    'cancellation closes the owned sheet and cancels queued prompts',
    (tester) async {
      await app(tester);
      final one = native('captcha', {
        'id': 'one',
        'source': '自编',
        'image': image,
      });
      final two = native('captcha', {
        'id': 'two',
        'source': '自编',
        'image': image,
      });
      await tester.pumpAndSettle();
      await native('cancelPrompt', {'id': 'two'});
      await native('cancelPrompt', {'id': 'one'});
      await tester.pumpAndSettle();
      expect(await one, isNull);
      expect(await two, isNull);
      expect(find.byType(SourceCaptchaInput), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('external application requires an explicit confirmation', (
    tester,
  ) async {
    await app(tester);
    final result = native('confirmOpenUrl', {
      'id': 'external',
      'source': '自编',
      'url': 'https://fixture.invalid/book',
    });
    await tester.pumpAndSettle();
    expect(find.text('打开外部应用？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
  testWidgets(
    'native operations receive view configuration but inspection never does',
    (tester) async {
      final host = await app(tester);
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SourcePlatform.channel,
        (call) async {
          calls.add(call);
          if (call.method == 'inspectScript') {
            return {
              'bookSourceUrl': 'https://fixture.invalid',
              'bookSourceName': '自编',
            };
          }
          return <String, dynamic>{};
        },
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SourcePlatform.channel,
          null,
        ),
      );
      await const SourcePlatform().run(
        BookSource({
          'bookSourceUrl': 'https://fixture.invalid',
          'bookSourceName': '自编',
        }),
        'explores',
      );
      await const SourcePlatform().inspectScript('var config={};');
      expect((calls.first.arguments as Map)['environment'], host.environment());
      expect(calls.last.arguments, isA<String>());
      expect(host.environment()['reader']['textSize'], state.fontSize);
      expect(host.environment().containsKey('login'), isFalse);
    },
  );
  testWidgets(
    'a background prompt is rejected instead of appearing on resume',
    (tester) async {
      await app(tester);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final result = native('captcha', {
        'id': 'background',
        'source': '自编',
        'image': image,
      });
      final expected = expectLater(result, throwsA(isA<PlatformException>()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await expected;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(SourceCaptchaInput), findsNothing);
    },
  );
  testWidgets(
    'verification handoff waits for Flutter resume without opening over another app',
    (tester) async {
      await app(tester);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final result = native('captcha', {
        'id': 'handoff',
        'source': '自编',
        'image': image,
      });
      await tester.pump();
      expect(find.byType(SourceCaptchaInput), findsNothing);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(SourceCaptchaInput), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    },
  );
}
