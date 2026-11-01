import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/offline_cache.dart';
import 'package:wenku8_flutter/offline_repository.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_platform.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_store.dart';

BookSource fixtureSource([String name = '甲']) => BookSource({
  'bookSourceName': name,
  'bookSourceUrl': 'https://$name.invalid',
  'searchUrl': '/search?q={{key}}&p={{page}}',
  'exploreUrl': '最近::/new?page={{page}}',
  'ruleSearch': {'bookList': '.book', 'name': 'a@text', 'bookUrl': 'a@href'},
  'ruleBookInfo': {'name': 'h1@text', 'tocUrl': '#toc@href'},
  'ruleToc': {
    'chapterList': '.chapter',
    'chapterName': '@text',
    'chapterUrl': '@href',
  },
  'ruleContent': {'content': '#content@text'},
});

class FixtureSourcePlatform extends SourcePlatform {
  final calls = <String>[];
  final detailNames = <String>[];
  final cancellations = <String>[];
  final imageRequests = <({String url, String? key, bool cachedOnly})>[];
  bool fail = false;
  bool slow = false;
  int active = 0, peak = 0;
  Completer<void>? blocked;
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
    calls.add('${source.name}:$operation:$page');
    active++;
    if (active > peak) peak = active;
    try {
      if (slow) await Future<void>.delayed(const Duration(milliseconds: 20));
      if (blocked != null) await blocked!.future;
      if (fail) throw const SourceFailure('书源返回 HTTP 503');
      switch (operation) {
        case 'explores':
          return [
            {'title': '最近', 'url': '/new?page={{page}}'},
          ];
        case 'search':
        case 'explore':
          return {
            'items': page > 1
                ? []
                : [
                    {
                      'name': '星海',
                      'author': '小舟',
                      'bookUrl': '${source.key}/book/1',
                      'coverUrl': '${source.key}/cover.jpg',
                      'kind': '奇幻 冒险',
                    },
                  ],
            'hasMore': page == 1,
          };
        case 'detail':
          detailNames.add('${book?['name'] ?? ''}');
          return {
            'name': '星海',
            'author': '小舟',
            'intro': '一段简介',
            'tocUrl': '${source.key}/toc',
            'bookUrl': url,
          };
        case 'toc':
          return [
            {'name': '第一卷', 'isVolume': true},
            {'name': '第一章', 'url': '${source.key}/chapter/1'},
            {'name': '第二章', 'url': '${source.key}/chapter/2'},
          ];
        case 'content':
          return '第一段。\n\n<!--image-->${source.key}/images/1.jpg<!--image-->\n\n第二段。';
      }
      throw StateError(operation);
    } finally {
      active--;
    }
  }

  @override
  Future<void> cancel(String requestId) async {
    cancellations.add(requestId);
  }

  @override
  Future<Uint8List> image({
    required String url,
    BookSource? source,
    String? sourceKey,
    String? referrer,
    bool cachedOnly = false,
    bool isCover = false,
    Map<String, dynamic>? book,
  }) async {
    imageRequests.add((
      url: url,
      key: sourceKey ?? source?.key,
      cachedOnly: cachedOnly,
    ));
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SourceStore store;
  late FixtureSourcePlatform platform;
  late SourceNovelRepository remote;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('custom-sources-');
    store = SourceStore(File('${root.path}/sources/index.json'));
    await store.load();
    platform = FixtureSourcePlatform();
    remote = SourceNovelRepository(store: store, platform: platform);
  });
  tearDown(() async {
    remote.dispose();
    store.dispose();
    await root.delete(recursive: true);
  });

  test(
    'fresh installation has no sources and makes no content requests',
    () async {
      expect(store.sources, isEmpty);
      expect((await remote.browse()).items, isEmpty);
      expect((await remote.searchPage('星海')).items, isEmpty);
      expect(platform.calls, isEmpty);
    },
  );
  test(
    'imports Legado JSON objects/lists; rejects incompatible and oversized input',
    () {
      expect(
        BookSource.parse(jsonEncode(fixtureSource().data)).single.name,
        '甲',
      );
      expect(
        BookSource.parse(
          jsonEncode([fixtureSource().data, fixtureSource().data]),
        ),
        hasLength(1),
      );
      expect(
        () => BookSource.parse('[{"bookSourceName":"无地址"}]'),
        throwsFormatException,
      );
      expect(
        () => BookSource({...fixtureSource().data, 'bookSourceType': 2}),
        throwsFormatException,
      );
      expect(
        () => BookSource.parse('x' * (8 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
    },
  );
  test(
    'source updates preserve disabled state and unknown rule fields',
    () async {
      final first = fixtureSource().copyWith(enabled: false);
      await store.saveSources([first]);
      await store.saveSources([
        BookSource({
          ...first.data,
          'bookSourceName': '新名称',
          'customField': 123,
        }),
      ]);
      expect(store.sources.single.name, '新名称');
      expect(store.sources.single.enabled, isFalse);
      expect(store.sources.single.data['customField'], 123);
      expect((await remote.searchPage('星海')).items, isEmpty);
    },
  );
  test(
    'sharing strips device credentials and preserves executable header rules',
    () {
      final source = BookSource({
        ...fixtureSource().data,
        'loginInfo': 'secret',
        'header':
            '{"Cookie":"secret","Authorization":"secret","User-Agent":"reader","X-Api-Key":"secret"}',
      });
      final encoded = jsonEncode(source.exportRules());
      expect(encoded, isNot(contains('secret')));
      expect(encoded, contains('reader'));
      final mapped = BookSource({
        ...source.data,
        'header': {'Cookie': 'secret', 'User-Agent': 'reader'},
      });
      expect(jsonEncode(mapped.exportRules()), isNot(contains('secret')));
      expect(mapped.data['header'], containsPair('Cookie', 'secret'));
      expect(
        BookSource({
          ...source.data,
          'header': '@js:secret',
        }).exportRules().containsKey('header'),
        isTrue,
      );
    },
  );
  test(
    'mixed imports preview unsupported entries without dropping valid sources',
    () {
      final report = SourceImportReport.parse(
        jsonEncode([
          fixtureSource().data,
          {...fixtureSource('音频').data, 'bookSourceType': 1},
        ]),
      );
      expect(report.sources, hasLength(1));
      expect(report.rejected, hasLength(1));
      expect(report.rejected.single, contains('音频'));
    },
  );
  test(
    'legacy rebind preserves chapter keys, snapshots and canonical identity after reopening',
    () async {
      final source = fixtureSource();
      await store.saveSources([source]);
      final target = (await remote.searchPage('星海')).items.single;
      final chapters = await remote.chapters(target.id);
      final old =
          Novel.fromSnapshot({
            ...target.toSnapshot(),
            'id': 42,
            'sourceId': null,
            'bookUrl': null,
            'tocUrl': null,
          }).withChapters([
            const NovelChapter('第一章', '', id: 101, volumeTitle: '第一卷'),
            const NovelChapter('第二章', '', id: 202, volumeTitle: '第一卷'),
          ]);
      final bound = await store.bindLegacy(old, target, chapters);
      expect(bound.id, 42);
      expect(bound.chapters.map((c) => c.id), [101, 202]);
      expect((await remote.detail(old)).id, 42);
      final reopen = SourceStore(store.file);
      await reopen.load();
      expect(
        reopen.remember(source, {'name': '星海', 'bookUrl': target.bookUrl}).id,
        42,
      );
      reopen.dispose();
      final bad = old.withChapters([const NovelChapter('不存在的章节', '', id: 999)]);
      await expectLater(
        store.bindLegacy(bad, target, chapters),
        throwsFormatException,
      );
      expect(store.book(42)!.chapters.first.id, 101);
    },
  );
  test(
    'same title in different sources gets distinct persistent IDs',
    () async {
      await store.saveSources([fixtureSource(), fixtureSource('乙')]);
      final results = await remote.searchPage('星海');
      expect(results.items, hasLength(2));
      expect(results.items[0].id, isNot(results.items[1].id));
      expect(
        results.items.every((b) => b.id >= 0x20000000 && b.id < 0x60000000),
        isTrue,
      );
      final reopened = SourceStore(store.file);
      await reopened.load();
      final again = reopened.remember(reopened.sources[0], {
        'name': '星海',
        'bookUrl': '${reopened.sources[0].key}/book/1',
      });
      expect(again.id, results.items[0].id);
      reopened.dispose();
    },
  );
  test(
    'source author labels normalize on remember and reopening while metadata retains its identity',
    () async {
      final source = fixtureSource();
      await store.saveSources([source]);
      final first = store.remember(source, {
        'name': '星海',
        'bookUrl': '${source.key}/book/1',
        'author': '作者：小舟',
        'complete': true,
      });
      expect(first.author, '小舟');
      final updated = store.remember(source, {
        'name': '星海',
        'bookUrl': first.bookUrl,
        'complete': false,
      });
      expect(updated.isComplete, isFalse);
      expect(updated.id, first.id);
      expect(updated.author, '小舟');
      await store.flush();
      final saved = jsonDecode(await store.file.readAsString()) as Map;
      (saved['books'] as List).first['author'] = '作者：小舟';
      await store.file.writeAsString(jsonEncode(saved));
      final reopened = SourceStore(store.file);
      await reopened.load();
      expect(reopened.book(first.id)!.author, '小舟');
      reopened.dispose();
      for (final (raw, expected) in [
        ('著者: 小舟', '小舟'),
        ('Author Mira Vale', 'Mira Vale'),
        ('作者菌', '作者菌'),
        ('The Author', 'The Author'),
      ]) {
        expect(sourceAuthorName(raw), expected);
      }
    },
  );

  test(
    'detail revalidates the selected listing name instead of a polluted stored title',
    () async {
      final source = fixtureSource();
      await store.saveSources([source]);
      final selected = store.remember(source, {
        'name': '星海',
        'bookUrl': '${source.key}/book/1',
      });
      store.remember(source, {'name': '错误的推荐标题', 'bookUrl': selected.bookUrl});
      expect(store.book(selected.id)!.title, '错误的推荐标题');
      final full = await remote.detail(selected);
      expect(platform.detailNames, ['星海']);
      expect(full.title, '星海');
      expect(full.id, selected.id);
      expect(store.book(selected.id)!.title, '星海');
    },
  );

  test(
    'search, detail, directory, inline images, cache and disabled-source reading form a complete loop',
    () async {
      final source = fixtureSource();
      await store.saveSources([source]);
      final cache = OfflineCacheStore(
        Directory('${root.path}/wenku8-offline-v1'),
      );
      final offline = OfflineNovelRepository(remote: remote, cache: cache);
      await offline.loadCache();
      final found = (await remote.searchPage('星海')).items.single;
      final full = await offline.detail(found);
      final chapters = await offline.chapters(found.id);
      expect(chapters.map((c) => c.volumeTitle).toSet(), {'第一卷'});
      expect(full.sourceId, source.key);
      expect(full.tocUrl, '${source.key}/toc');
      final body = await offline.chapterContent(found.id, chapters.first);
      final content = await ReaderContent.parse(body);
      expect(content.paragraphs, hasLength(3));
      expect(content.illustrations, hasLength(1));
      await store.configure(source.copyWith(enabled: false));
      platform.fail = true;
      expect(await offline.chapterContent(found.id, chapters.first), body);
      final cached = await cache.readBook(found.id);
      expect(cached!.sourceId, source.key);
      expect(cached.chapters.first.url, chapters.first.url);
      expect((await offline.chapters(found.id)).first.id, chapters.first.id);
      offline.dispose();
      cache.dispose();
    },
  );
  test(
    'chapter reorder keeps stable URL IDs; removed source keeps index and image namespace',
    () async {
      final source = fixtureSource();
      await store.saveSources([source]);
      final book = (await remote.searchPage('星海')).items.single;
      final chapters = await remote.chapters(book.id);
      final reordered = await store.rememberChapters(book.id, [
        {'name': '插入新章', 'url': '${source.key}/chapter/0'},
        {'name': '第二章', 'url': chapters.last.url},
        {'name': '第一章', 'url': chapters.first.url},
      ]);
      expect(reordered[1].id, chapters.last.id);
      expect(reordered[2].id, chapters.first.id);
      await store.remove(source);
      expect((await remote.find(book.id))!.id, book.id);
      await remote.cover(book.id);
      expect(platform.imageRequests.single.cachedOnly, isTrue);
      expect(platform.imageRequests.single.key, source.key);
      await store.saveSources([source]);
      expect(
        (await remote.searchPage('星海', refresh: true)).items.single.id,
        book.id,
      );
    },
  );
  test(
    'no old provider is contacted when a legacy cache and bookmarks are read',
    () async {
      final legacy = Novel(
        id: 123,
        title: '旧书',
        author: '作者',
        genre: '奇幻',
        summary: '简介',
        colors: const [Colors.grey, Colors.blue],
        chapters: const [NovelChapter('第一章', '', id: 11)],
      );
      final position = ReadingPosition(
        chapter: 0,
        chapterId: 11,
        offset: 120,
        fraction: .4,
        fontSize: 19,
        width: 390,
        updatedAt: 1,
      );
      final bookmark = ReaderBookmark(
        id: 'b1',
        chapterTitle: '第一章',
        position: position,
        quote: '珍藏的句子',
      );
      final records = <String, Object>{
        'shelf': ['123'],
        'novel_meta_123': jsonEncode(legacy.toSnapshot()),
        'reading_position_123': jsonEncode(position.toJson()),
        'reader_bookmarks_123': jsonEncode([bookmark.toJson()]),
      };
      SharedPreferences.setMockInitialValues(records);
      final state = await LibraryState.load();
      final cache = OfflineCacheStore(
        Directory('${root.path}/wenku8-offline-v1'),
      );
      await cache.saveBook(legacy, epoch: cache.epochFor(123));
      await cache.saveChapter(123, 11, '旧缓存正文', epoch: cache.epochFor(123));
      final remote = SourceNovelRepository(
        store: store,
        platform: platform,
        legacyBook: state.cachedNovel,
      );
      final offline = OfflineNovelRepository(remote: remote, cache: cache);
      await offline.loadCache();
      expect((await offline.find(123))!.title, '旧书');
      expect(await offline.chapterContent(123, legacy.chapters.first), '旧缓存正文');
      expect((await offline.chapters(123)).first.id, 11);
      expect(state.shelf, contains(123));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('reader_bookmarks_123'),
        records['reader_bookmarks_123'],
      );
      expect(
        prefs.getString('reading_position_123'),
        records['reading_position_123'],
      );
      expect(platform.calls, isEmpty);
      offline.dispose();
      remote.dispose();
      cache.dispose();
      state.dispose();
    },
  );
  test(
    'multi-source fanout is bounded and cancellation stops queued batches',
    () async {
      await store.saveSources([
        for (var i = 0; i < 7; i++) fixtureSource('$i'),
      ]);
      platform.slow = true;
      final found = <Novel>[];
      for (var page = 1; page < 12; page++) {
        final result = await remote.searchPage('星海', page: page);
        found.addAll(result.items);
        if (!result.hasMore) break;
      }
      expect(found, hasLength(7));
      expect(platform.peak, lessThanOrEqualTo(3));
      platform.calls.clear();
      platform.blocked = Completer<void>();
      final result = remote.searchPage('另一本');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await remote.cancelSearch();
      platform.blocked!.complete();
      await expectLater(result, throwsA(isA<SourceFailure>()));
      expect(platform.calls, hasLength(3));
      expect(platform.cancellations, hasLength(3));
    },
  );
}
