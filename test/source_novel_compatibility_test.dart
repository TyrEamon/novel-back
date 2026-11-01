import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_login_page.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_store.dart';
import 'custom_sources_test.dart' show FixtureSourcePlatform, fixtureSource;
import 'support/visual_review.dart';

class _NovelPlatform extends FixtureSourcePlatform {
  bool warn = true;
  int loginUiLoads = 0;
  Map<String, dynamic> ui({bool changed = false}) => {
    'rows': [
      {'name': '账号', 'type': 'text'},
      {'name': '密码', 'type': 'password'},
      {
        'name': '获取',
        'label': changed ? '重新发送' : '获取验证码',
        'type': 'button',
        'action': 'send()',
      },
    ],
    'info': {'账号': changed ? '已更新' : '原输入', '密码': 'fixture-only'},
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
    if (operation == 'loginUi') {
      loginUiLoads++;
      return ui();
    }
    if (operation == 'login') {
      return {...ui(changed: true), 'version': 1, 'refreshExplore': true};
    }
    final result = await super.run(
      source,
      operation,
      url: url,
      key: key,
      page: page,
      book: book,
      chapter: chapter,
      requestId: requestId,
    );
    if (operation == 'detail') {
      return {
        ...Map<String, dynamic>.from(result as Map),
        'ruleWarnings': [if (warn) '书源简介：请求的安全连接失败'],
      };
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadReviewFonts();
  });
  late Directory root;
  late SourceStore store;
  late _NovelPlatform platform;
  late SourceNovelRepository repo;
  late LibraryState state;
  final source = fixtureSource('自编小说');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = await LibraryState.load();
    root = await Directory.systemTemp.createTemp('novel-compat-');
    store = SourceStore(File('${root.path}/index.json'));
    await store.saveSources([source]);
    platform = _NovelPlatform();
    repo = SourceNovelRepository(store: store, platform: platform);
  });
  tearDown(() async {
    repo.dispose();
    store.dispose();
    state.dispose();
    await root.delete(recursive: true);
  });
  Widget app(Widget child, GlobalKey capture) => RepaintBoundary(
    key: capture,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: novelTheme(Brightness.light, fontFamily: 'Roboto'),
      home: child,
    ),
  );

  test('only text novel sources are imported in this stage', () {
    for (final type in [1, 2, 3, 4]) {
      expect(
        () => BookSource({...source.data, 'bookSourceType': type}),
        throwsFormatException,
      );
    }
  });

  test(
    'optional warnings are transient and clear after a successful retry',
    () async {
      final book = store.remember(source, {
        'name': '星海',
        'bookUrl': '${source.key}/book/1',
      });
      await repo.detail(book);
      expect(repo.detailWarnings(book.id), ['书源简介：请求的安全连接失败']);
      final reopened = SourceStore(store.file);
      await reopened.load();
      expect(reopened.book(book.id)!.title, '星海');
      expect(await store.file.readAsString(), isNot(contains('ruleWarnings')));
      reopened.dispose();
      platform.warn = false;
      await repo.detail(book);
      expect(repo.detailWarnings(book.id), isEmpty);
    },
  );

  testWidgets(
    'a V1 callback applies changed fields and labels without reloading the old form',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final capture = GlobalKey();
      var changes = 0;
      repo.addListener(() => changes++);
      await tester.pumpWidget(
        app(SourceLoginPage(source: source, repository: repo), capture),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('source-login-action-send()')),
      );
      await tester.pumpAndSettle();
      expect(find.text('已更新'), findsOneWidget);
      expect(find.text('重新发送'), findsOneWidget);
      expect(platform.loginUiLoads, 1);
      expect(changes, 1);
      expect(tester.takeException(), isNull);
      await captureReview(tester, capture, 'novel-login-v1-callback');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'optional rule problems leave the detail and reading entry usable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final book = store.remember(source, {
        'name': '星海',
        'bookUrl': '${source.key}/book/1',
      });
      final full = await tester.runAsync(
        () async => (await repo.detail(
          book,
        )).withChapters(await repo.chapters(book.id)),
      );
      final capture = GlobalKey();
      await tester.pumpWidget(
        app(DetailPage(novel: full!, state: state, repository: repo), capture),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('detail-source-warnings')),
        findsOneWidget,
      );
      expect(find.text('书源简介：请求的安全连接失败'), findsOneWidget);
      expect(find.text('书籍详情加载失败'), findsNothing);
      expect(find.byKey(const ValueKey('detail-read-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureReview(tester, capture, 'novel-detail-optional-warning');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
