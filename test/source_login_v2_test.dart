import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_login_page.dart';
import 'package:wenku8_flutter/sources/source_platform.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_store.dart';
import 'support/visual_review.dart';

class _V2 extends SourcePlatform {
  final forms = <Map<String, dynamic>>[];
  Map<String, dynamic> render(Map<String, dynamic> state) => {
    'version': 2,
    'state': state,
    'info': {'phone': 'stored'},
    'rows': [
      {'name': '自编登录说明', 'type': 'label'},
      {'name': '手机号', 'key': 'phone', 'type': 'text'},
      if (state['step'] == 'code')
        {'name': '验证码', 'key': 'code', 'type': 'text', 'hint': '6位数字'},
      {'name': '发送验证码', 'type': 'button', 'action': 'send', 'countdown': 2},
      if (state['step'] == 'code')
        {'name': '登录', 'type': 'button', 'action': 'verify'},
    ],
  };
  @override
  Future<dynamic> run(
    BookSource source,
    String operation, {
    String? url,
    String key = '',
    int page = 1,
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
    String? requestId,
  }) async {
    if (operation == 'loginUi') return render({});
    final form = Map<String, dynamic>.from(book!['loginInfo'] as Map);
    forms.add(form);
    if (key == 'send') {
      if (form['phone'] == '') {
        return {
          'version': 2,
          'error': {'phone': '请输入手机号'},
        };
      }
      return render({'step': 'code'});
    }
    if (form['code'] == '123456') {
      return {
        'version': 2,
        'login': {'account': 'fixture'},
        'close': true,
      };
    }
    return {
      'version': 2,
      'error': {'code': '验证码不正确'},
    };
  }

  @override
  Future<void> cancel(String requestId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadReviewFonts();
  });
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('login-v2-');
  });
  tearDown(() => root.delete(recursive: true));
  final source = BookSource({
    'bookSourceName': '自编登录',
    'bookSourceUrl': 'https://fixture.invalid',
    'loginUi': '{"version":2}',
  });

  test('mainJs JSON retains the upstream field and remains searchable', () {
    final script = BookSource({
      ...source.data,
      'mainJs': 'function search(){}',
    });
    expect(script.searchable, isTrue);
    expect(script.exportRules()['mainJs'], 'function search(){}');
  });

  testWidgets(
    'v2 preserves input, shows errors, renders stages and counts down',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final capture = GlobalKey();
      final store = SourceStore(File('${root.path}/index.json'));
      final platform = _V2();
      final repo = SourceNovelRepository(store: store, platform: platform);
      addTearDown(store.dispose);
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: novelTheme(Brightness.light, fontFamily: 'Roboto'),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SourceLoginPage(source: source, repository: repo),
                    ),
                  ),
                  child: const Text('打开登录'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开登录'));
      await tester.pumpAndSettle();
      expect(find.text('自编登录说明'), findsOneWidget);
      await captureReview(tester, capture, 'source-login-v2-initial');
      expect(find.byKey(const ValueKey('source-login-submit')), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'stored',
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byKey(const ValueKey('source-login-action-send')));
      await tester.pumpAndSettle();
      expect(find.text('请输入手机号'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'fixture-phone');
      await tester.tap(find.byKey(const ValueKey('source-login-action-send')));
      await tester.pumpAndSettle();
      expect(find.text('发送验证码 (2s)'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'fixture-phone',
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('发送验证码 (2s)'), findsNothing);
      await tester.enterText(find.byType(TextField).last, 'wrong');
      await tester.ensureVisible(
        find.byKey(const ValueKey('source-login-action-verify')),
      );
      await tester.tap(
        find.byKey(const ValueKey('source-login-action-verify')),
      );
      await tester.pumpAndSettle();
      expect(find.text('验证码不正确'), findsOneWidget);
      await captureReview(tester, capture, 'source-login-v2-validation');
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'wrong',
      );
      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.ensureVisible(
        find.byKey(const ValueKey('source-login-action-verify')),
      );
      await tester.tap(
        find.byKey(const ValueKey('source-login-action-verify')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SourceLoginPage), findsNothing);
      expect(platform.forms.last, {'phone': 'fixture-phone', 'code': '123456'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
