import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_account.dart';
import 'package:wenku8_flutter/sources/source_account_card.dart';
import 'package:wenku8_flutter/sources/source_pages.dart';
import 'package:wenku8_flutter/sources/source_platform.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_store.dart';
import 'support/visual_review.dart';

final _source = BookSource({
  'bookSourceName': '自编账号书源',
  'bookSourceUrl': 'https://account.invalid',
  'loginUrl': 'https://account.invalid/login',
  'ruleAccount': {
    'verify': {'url': '/account', 'loggedIn': r'$.loggedIn'},
    'shelf': {
      'url': '/shelf?page={{page}}',
      'bookList': r'$.books[*]',
      'name': r'$.name',
      'bookUrl': r'$.url',
    },
    'checkIn': {'url': '/check-in', 'success': r'$.success'},
  },
});

class _AccountPlatform extends SourcePlatform {
  int statusReads = 0;
  final actions = <String>[];
  String status = 'saved';
  bool checkedIn = false, failSecondPage = false, repeatPage = false;
  Completer<void>? gate;
  @override
  Future<SourceAccountStatus> accountStatus(BookSource source) async {
    statusReads++;
    return SourceAccountStatus(
      status: status,
      loginAvailable: true,
      canVerify: sourceCanVerifyAccount(source),
      canSync: source.data['ruleAccount'] != null,
      canCheckIn: source.data['ruleAccount'] != null,
      checkedInToday: checkedIn,
      checkedAt: status == 'verified' ? DateTime(2026, 10, 18, 18, 30) : null,
    );
  }

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
    actions.add(operation);
    if (operation == 'accountVerify') {
      status = 'verified';
      return true;
    }
    if (operation == 'accountCheckIn') {
      checkedIn = true;
      return {'already': false};
    }
    if (gate != null) await gate!.future;
    if (failSecondPage && page == 2) throw const SourceFailure('自编第二页请求失败');
    return {
      'items': [
        for (final i in page == 1 ? [1, 2] : [2, 3])
          {'name': '星海$i', 'bookUrl': '${source.key}/book/$i'},
      ],
      'hasMore': page == 1 || repeatPage,
      'pageUrl': '${source.key}/shelf?page=${repeatPage ? 1 : page}',
      'nextUrl': page == 1 ? '${source.key}/shelf?page=2' : null,
    };
  }

  @override
  Future<void> cancel(String requestId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SourceStore store;
  late SourceNovelRepository repo;
  late _AccountPlatform platform;
  late LibraryState state;
  setUpAll(() async {
    await loadReviewFonts();
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('source-account-');
    store = SourceStore(File('${root.path}/index.json'));
    await store.saveSources([_source]);
    platform = _AccountPlatform();
    repo = SourceNovelRepository(store: store, platform: platform);
    SharedPreferences.setMockInitialValues({});
    state = await LibraryState.load();
  });
  tearDown(() async {
    repo.dispose();
    store.dispose();
    state.dispose();
    await root.delete(recursive: true);
  });

  test(
    'account reads coalesce; a saved session never starts remote actions',
    () async {
      final first = repo.accountStatus(_source);
      expect(identical(first, repo.accountStatus(_source)), isTrue);
      expect((await first).label, '已保存会话');
      expect(platform.statusReads, 1);
      expect(platform.actions, isEmpty);
      await repo.verifyAccount(_source);
      expect((await repo.accountStatus(_source)).label, '已验证登录');
      expect(platform.statusReads, 2);
      await repo.checkIn(_source, requestId: 'check-in');
      expect((await repo.accountStatus(_source)).checkedInToday, isTrue);
    },
  );
  test('same-key rule edits cannot reuse old account capabilities', () async {
    expect((await repo.accountStatus(_source)).canVerify, isTrue);
    final edited = BookSource({..._source.data}..remove('ruleAccount'));
    expect((await repo.accountStatus(edited)).canVerify, isFalse);
    expect(platform.statusReads, 2);
  });
  test(
    'cloud shelf metadata does not erase a reserved cached directory',
    () async {
      final recovered = Novel(
        id: 0x20000800,
        title: '星海1',
        author: '作者',
        genre: '',
        summary: '',
        colors: const [Colors.grey, Colors.black],
        sourceId: _source.key,
        bookUrl: '${_source.key}/book/1',
        chapters: [
          NovelChapter(
            '原章节',
            '',
            id: 87,
            url: '${_source.key}/chapter/original',
          ),
        ],
        chapterCount: 1,
      );
      store.reserveBooks([recovered]);
      await state.setShelfMembership(recovered.id, true, novel: recovered);
      await repo.syncSourceShelf(_source, state, requestId: 'recovered');
      expect(store.book(recovered.id)!.chapters.single.id, 87);
      expect(state.cachedNovel(recovered.id)!.chapters.single.id, 87);
    },
  );
  test(
    'login without explicit account rules and disabled sources are not auto-probed',
    () async {
      await repo.loginFinished(
        BookSource({
          'bookSourceName': 'legacy',
          'bookSourceUrl': 'https://legacy.invalid',
          'loginCheckJs': 'result',
        }),
      );
      await repo.loginFinished(_source.copyWith(enabled: false));
      expect(platform.actions, isEmpty);
      await repo.loginFinished(_source);
      expect(platform.actions, ['accountVerify']);
    },
  );
  test(
    'all cloud shelf pages merge once without deleting books or changing bookmarks',
    () async {
      final initial = store.remember(_source, {
        'name': '星海1',
        'bookUrl': '${_source.key}/book/1',
      });
      await store.rememberChapters(initial.id, [
        {'name': '第一章', 'url': '${_source.key}/chapter/one'},
      ]);
      final original = store.book(initial.id)!;
      await state.setShelfMembership(original.id, true, novel: original);
      await state.addShelfIds([123]);
      const position = ReadingPosition(
        chapter: 0,
        chapterId: 1,
        offset: 30,
        fraction: .2,
        fontSize: 20,
        width: 390,
        updatedAt: 1,
      );
      await state.addBookmark(
        novel: original,
        position: position,
        quote: '喜欢的一句话。',
      );
      var notifications = 0;
      state.addListener(() => notifications++);
      expect(await repo.syncSourceShelf(_source, state, requestId: 'sync'), 2);
      expect(state.shelf, containsAll([123, original.id]));
      expect(state.shelf.length, 4);
      expect(state.bookmarksFor(original.id).single.quote, '喜欢的一句话。');
      expect(notifications, 1);
      final restored = await LibraryState.load();
      expect(restored.shelf, state.shelf);
      expect(restored.cachedNovel(original.id)?.title, '星海1');
      restored.dispose();
      expect(
        await repo.syncSourceShelf(_source, state, requestId: 'sync-again'),
        0,
      );
      expect(store.books.length, 3);
    },
  );
  test(
    'failed/repeated/cancelled pagination never imports a partial shelf',
    () async {
      platform.failSecondPage = true;
      await expectLater(
        repo.syncSourceShelf(_source, state, requestId: 'failure'),
        throwsA(isA<SourceFailure>()),
      );
      expect(state.shelf, isEmpty);
      platform.failSecondPage = false;
      platform.repeatPage = true;
      await expectLater(
        repo.syncSourceShelf(_source, state, requestId: 'repeat'),
        throwsA(isA<SourceFailure>()),
      );
      expect(state.shelf, isEmpty);
      platform.repeatPage = false;
      platform.gate = Completer<void>();
      final pending = repo.syncSourceShelf(_source, state, requestId: 'cancel');
      final assertion = expectLater(pending, throwsA(isA<SourceFailure>()));
      await repo.cancelAccountRequest('cancel');
      platform.gate!.complete();
      await assertion;
      expect(state.shelf, isEmpty);
    },
  );
  for (final width in [320.0, 430.0]) {
    testWidgets(
      'compact account card at $width retains glass actions and live status',
      (tester) async {
        tester.view.physicalSize = Size(width, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final capture = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: novelTheme(
                Brightness.light,
                fontFamily: 'Roboto',
              ),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 950),
                  textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                ),
                child: SourceManagerPage(
                  repository: repo,
                  library: state,
                  reduceMotion: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('已保存会话'), findsOneWidget);
        expect(find.text('合并云书架'), findsOneWidget);
        expect(platform.actions, isEmpty);
        await tester.ensureVisible(
          find.byKey(ValueKey('source-account-verify-${_source.key}')),
        );
        await tester.tap(
          find.byKey(ValueKey('source-account-verify-${_source.key}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('已验证登录'), findsOneWidget);
        await tester.tap(
          find.byKey(ValueKey('source-account-checkin-${_source.key}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('今日已签到'), findsOneWidget);
        await captureReview(
          tester,
          capture,
          'source-account-card-${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'unsupported actions remain absent and disabled source makes no account requests',
    (tester) async {
      final legacy = BookSource({
        'bookSourceName': '无账号规则',
        'bookSourceUrl': 'https://legacy.invalid',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SourceAccountPanel(source: legacy, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('合并云书架'), findsNothing);
      expect(find.text('签到'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: SourceAccountPanel(
            source: _source.copyWith(enabled: false),
            repository: repo,
            library: state,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('验证登录'));
      expect(platform.actions, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
