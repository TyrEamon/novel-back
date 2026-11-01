import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/main.dart';
import 'package:wenku8_flutter/pages.dart' show NovelRow;
import 'package:wenku8_flutter/my_page.dart';
import 'package:wenku8_flutter/sources/source_store.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_pages.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_login_page.dart';
import 'package:wenku8_flutter/updates/update_page.dart';
import 'package:wenku8_flutter/offline_cache.dart';
import 'package:wenku8_flutter/offline_repository.dart';
import 'custom_sources_test.dart' show FixtureSourcePlatform, fixtureSource;

class _Platform extends FixtureSourcePlatform {
  Map<String, dynamic> login = {};
  int webLogins = 0;
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
      return {
        'rows': [
          {'name': '账号', 'label': '账号', 'type': 'text'},
          {'name': '密码', 'label': '密码', 'type': 'password'},
        ],
        'info': login,
        'webUrl': '${source.key}/login',
      };
    }
    if (operation == 'login') {
      login = Map<String, dynamic>.from(book!['loginInfo'] as Map);
      return true;
    }
    if (operation == 'explores') {
      return [
        for (final (name, start, end) in [
          ('分类', 0, 400),
          ('榜单', 400, 700),
          ('其他', 700, 1000),
        ]) ...[
          {'title': name, 'url': ''},
          for (var i = start; i < end; i++)
            {
              'title': '标签$i',
              'url': '/tags/$i',
              'style': {'layout_flexBasisPercent': .5},
            },
        ],
      ];
    }
    return super.run(
      source,
      operation,
      url: url,
      key: key,
      page: page,
      book: book,
      chapter: chapter,
      requestId: requestId,
    );
  }

  @override
  Future<String?> pick() async => jsonEncode([fixtureSource().data]);
  @override
  Future<void> clearSession(source) async {
    login.clear();
  }

  @override
  Future<void> openLogin(BookSource source, {required String requestId}) async {
    webLogins++;
  }
}

class _DiscoverySearchPlatform extends _Platform {
  final searchKeys = <String>[];
  bool rejectSearch = false;
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
    if (operation == 'explore') return {'items': [], 'hasMore': false};
    if (operation == 'search') {
      searchKeys.add(key);
      if (rejectSearch) throw const SourceFailure('通用搜索规则执行失败');
      return {
        'items': [
          for (var i = 0; i < 72; i++)
            {
              'name': '不相关的自编作品 $i',
              'bookUrl': '${source.key}/book/unrelated/$i',
            },
          if (key == '龍與後記')
            {
              'name': '龍與後記',
              'author': '自编作者',
              'bookUrl': '${source.key}/book/fixture',
            },
        ],
        'hasMore': false,
      };
    }
    return super.run(
      source,
      operation,
      url: url,
      key: key,
      page: page,
      book: book,
      chapter: chapter,
      requestId: requestId,
    );
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('SOURCE_VISUALS')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final folder =
        Platform.environment['SOURCE_VISUAL_OUTPUT'] ?? 'build/source-visuals';
    final file = File('$folder/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}

Finder _icon(String label) =>
    find.byWidgetPredicate((w) => w is GlassIconButton && w.label == label);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, asset) in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/cupertino_icons/CupertinoIcons',
        'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      ),
    ]) {
      final loader = FontLoader(family)..addFont(rootBundle.load(asset));
      await loader.load();
    }
  });
  late Directory root;
  late SourceStore store;
  late SourceNovelRepository repo;
  late LibraryState state;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('source-ui-');
    store = SourceStore(File('${root.path}/index.json'));
    await store.load();
    repo = SourceNovelRepository(store: store, platform: _Platform());
    SharedPreferences.setMockInitialValues({
      'readerChromeHintSeen': true,
      'appTypeface': 'sourceHanSerif',
    });
    state = await LibraryState.load();
  });
  tearDown(() async {
    state.dispose();
    repo.dispose();
    store.dispose();
    await root.delete(recursive: true);
  });
  testWidgets(
    'zero-source discovery, manual import preview and source discovery keep existing UI',
    (tester) async {
      tester.view.physicalSize = const Size(394, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: NovelApp(state: state, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('从自己的书源开始'), findsOneWidget);
      await _capture(tester, '01-discovery-empty');
      await tester.tap(find.byKey(const ValueKey('discover-import-sources')));
      await tester.pumpAndSettle();
      expect(find.text('书源管理'), findsOneWidget);
      await _capture(tester, '02-source-manager');
      await tester.tap(find.byKey(const ValueKey('source-import-file')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 80 && find.text('确认导入').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('确认导入'), findsOneWidget);
      expect(store.sources, isEmpty);
      expect(find.byKey(const ValueKey('source-import-risk')), findsOneWidget);
      expect(find.text(fixtureSource().key), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('source-import-policy')));
      await tester.pumpAndSettle();
      expect(find.text('尊重作品与授权'), findsOneWidget);
      expect(store.sources, isEmpty);
      await tester.tap(_icon('返回'));
      await tester.pumpAndSettle();
      await _capture(tester, '03-import-preview');
      await tester.tap(find.byKey(const ValueKey('confirm-source-import')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 80 && find.text('甲').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pumpAndSettle();
      }
      expect(store.sources, hasLength(1));
      expect(find.text('甲'), findsOneWidget);
      await _capture(tester, '04-source-card');
      await tester.tap(_icon('新建书源'));
      await tester.pumpAndSettle();
      expect(find.text('书源名称'), findsOneWidget);
      await _capture(tester, '05-source-editor');
      await tester.tap(_icon('保存书源'));
      await tester.pumpAndSettle();
      expect(find.text('书源缺少名称或 bookSourceUrl'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      var saved = false;
      store.flush().then((_) => saved = true);
      for (var i = 0; i < 80 && !saved; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      expect(saved, isTrue);
    },
  );
  testWidgets(
    'my page contains source management instead of the old platform account',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light, fontFamily: 'Roboto'),
          home: MyPage(state: state, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('my-sources')), findsOneWidget);
      expect(find.text('登录文库账号'), findsNothing);
      expect(find.byKey(const ValueKey('my-bookmarks')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'discovery search submits typed simplified text through the offline wrapper and renders traditional results',
    (tester) async {
      final platform = _DiscoverySearchPlatform();
      final remote = SourceNovelRepository(store: store, platform: platform);
      final cache = OfflineCacheStore(Directory('${root.path}/offline'));
      final offline = OfflineNovelRepository(remote: remote, cache: cache);
      await tester.runAsync(() => store.saveSources([fixtureSource()]));
      tester.view.physicalSize = const Size(394, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: NovelApp(state: state, repository: offline),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_icon('搜索'));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('expanded-search-input'));
      await tester.enterText(input, '龙与后记');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      for (var i = 0; i < 80 && find.text('龍與後記').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pumpAndSettle();
      }
      expect(platform.searchKeys, ['龙与后记', '龍與後記']);
      expect(find.text('龍與後記'), findsWidgets);
      expect(find.byType(NovelRow), findsOneWidget);
      expect(find.text('找到 1 个结果'), findsOneWidget);
      await _capture(tester, '09-discovery-search-variants');
      platform.rejectSearch = true;
      await tester.enterText(input, 'new');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      for (var i = 0; i < 80 && find.text('搜索未完成').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pumpAndSettle();
      }
      expect(platform.searchKeys.last, 'new');
      await _capture(tester, '10-discovery-search-error');
      expect(find.text('搜索未完成'), findsOneWidget);
      expect(find.text('通用搜索规则执行失败'), findsOneWidget);
      expect(find.text('没有找到相关故事'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      offline.dispose();
      remote.dispose();
    },
  );
  testWidgets(
    'source manager keeps four actions and many groups on single rails',
    (tester) async {
      await tester.runAsync(
        () => store.saveSources([
          for (var i = 0; i < 30; i++)
            BookSource({
              ...fixtureSource('书源$i').data,
              'bookSourceGroup': '分组$i',
            }),
        ]),
      );
      tester.view.physicalSize = const Size(394, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp(
            theme: novelTheme(Brightness.light, fontFamily: 'Roboto'),
            home: SourceManagerPage(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final actions = [
        for (final name in ['file', 'url', 'paste', 'export'])
          tester.getRect(find.byKey(ValueKey('source-import-$name'))),
      ];
      for (final action in actions) {
        expect(action.top, actions.first.top);
        expect(action.left, greaterThanOrEqualTo(24));
        expect(action.right, lessThanOrEqualTo(370));
      }
      final rail = find.byKey(const ValueKey('source-group-rail'));
      expect(tester.getSize(rail).height, lessThanOrEqualTo(64));
      expect(
        tester
            .getRect(
              find.byKey(ValueKey('source-card-${store.sources.first.key}')),
            )
            .top,
        lessThan(430),
      );
      await _capture(tester, '11-source-manager-compact');
      await tester.drag(rail, const Offset(-1200, 0));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('source-group-分组20')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('source-group-分组20')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('source-card-${store.sources[20].key}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('source-card-${store.sources.first.key}')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'source manager fits compact phone, landscape and tablet with larger text',
    (tester) async {
      await tester.runAsync(
        () => store.saveSources([
          fixtureSource('中文长名称的书源'),
          fixtureSource('另一个'),
        ]),
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [
        const Size(320, 640),
        const Size(800, 400),
        const Size(1200, 800),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: novelTheme(Brightness.light, fontFamily: 'Roboto'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: SourceManagerPage(repository: repo),
          ),
        );
        await tester.pumpAndSettle();
        final actionY = [
          for (final name in ['file', 'url', 'paste', 'export'])
            tester.getRect(find.byKey(ValueKey('source-import-$name'))).top,
        ];
        expect(actionY.every((y) => y == actionY.first), isTrue);
        expect(tester.takeException(), isNull, reason: '$size');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'discovery categories are grouped, searchable and lazily built using shared glass controls',
    (tester) async {
      await tester.runAsync(() => store.saveSources([fixtureSource()]));
      tester.view.physicalSize = const Size(394, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp(
            theme: novelTheme(Brightness.light, fontFamily: 'Roboto'),
            home: Scaffold(body: SourceDiscoveryChoices(repository: repo)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('分类 · 400 项'), findsOneWidget);
      expect(find.byType(GlassTextButton).evaluate().length, lessThan(100));
      final first = tester.getRect(
        find.byKey(const ValueKey('discovery-category-/tags/0')),
      );
      final third = tester.getRect(
        find.byKey(const ValueKey('discovery-category-/tags/2')),
      );
      expect(first.top, third.top);
      await _capture(tester, '06-discovery-categories');
      await tester.tap(find.byKey(const ValueKey('discovery-group-榜单')));
      await tester.pumpAndSettle();
      expect(find.text('榜单 · 300 项'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('discovery-category-/tags/400')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('discovery-category-/tags/0')),
        findsNothing,
      );
      await _capture(tester, '12-discovery-category-group');
      await tester.enterText(
        find.byKey(const ValueKey('discovery-choice-search')),
        '标签999',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('discovery-category-/tags/999')),
        findsOneWidget,
      );
      expect(find.text('标签998'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('discovery-choice-search')),
        '',
      );
      await tester.pumpAndSettle();
      expect(find.text('榜单 · 300 项'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'discovery category picker fits a compact keyboard viewport and restores the selected group',
    (tester) async {
      final source = fixtureSource('名称较长的自编书源');
      await tester.runAsync(() async {
        await store.saveSources([source]);
        await store.select(source.key, '/tags/750');
      });
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light, fontFamily: 'Roboto'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => chooseSourceDiscovery(context, repo),
                  child: const Text('选择分类'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择分类'));
      await tester.pumpAndSettle();
      expect(find.text('其他 · 300 项'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const ValueKey('discovery-choice-search')),
        '标签999',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('discovery-category-/tags/999')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'source login uses unified fields, password autofill and source-scoped actions',
    (tester) async {
      final source = BookSource({
        ...fixtureSource().data,
        'loginUrl': '@js:function login(){}',
      });
      await tester.runAsync(() => store.saveSources([source]));
      tester.view.physicalSize = const Size(394, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp(
            theme: novelTheme(Brightness.light, fontFamily: 'Roboto'),
            home: SourceLoginPage(source: source, repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields, hasLength(2));
      expect(fields[0].autofillHints, contains(AutofillHints.username));
      expect(fields[1].autofillHints, contains(AutofillHints.password));
      expect(fields[1].obscureText, isTrue);
      await _capture(tester, '07-source-login');
      await tester.enterText(find.byType(TextField).at(0), 'fixture-user');
      await tester.enterText(find.byType(TextField).at(1), 'fixture-value');
      await tester.ensureVisible(
        find.byKey(const ValueKey('source-login-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('source-login-submit')));
      await tester.pumpAndSettle();
      expect((repo.platform as _Platform).login, {
        '账号': 'fixture-user',
        '密码': 'fixture-value',
      });
      var notifications = 0;
      repo.addListener(() => notifications++);
      await tester.ensureVisible(
        find.byKey(const ValueKey('source-login-web')),
      );
      await tester.tap(find.byKey(const ValueKey('source-login-web')));
      await tester.pumpAndSettle();
      expect((repo.platform as _Platform).webLogins, 1);
      expect(notifications, 1);
      expect(find.textContaining('书目会自动重新加载'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'new display branding is applied without changing source and reader entry points',
    (tester) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp(
            theme: novelTheme(Brightness.light, fontFamily: 'Roboto'),
            home: const AppUpdatePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('关于纸间文库'), findsOneWidget);
      expect(find.text('纸间文库'), findsOneWidget);
      expect(find.text('关于轻小说文库'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('about-responsible-use')),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('about-responsible-use')));
      await tester.pumpAndSettle();
      expect(find.text('使用与风险声明'), findsOneWidget);
      expect(find.text('尊重作品与授权'), findsOneWidget);
      await _capture(tester, '08-responsible-use');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
