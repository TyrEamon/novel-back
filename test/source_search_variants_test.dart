import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_language.dart';
import 'package:wenku8_flutter/book_search.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_store.dart';

import 'custom_sources_test.dart' show FixtureSourcePlatform, fixtureSource;

typedef _Request = ({String source, String key, String? url, int page});

class _SearchPlatform extends FixtureSourcePlatform {
  final requests = <_Request>[];
  late Future<Map<String, dynamic>> Function(_Request) reply;
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
    if (operation != 'search') {
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
    final request = (source: source.key, key: key, url: url, page: page);
    requests.add(request);
    active++;
    if (active > peak) peak = active;
    try {
      return await reply(request);
    } finally {
      active--;
    }
  }
}

Map<String, dynamic> _page(
  _Request request,
  List<int> ids, {
  bool more = false,
  String? next,
}) => {
  'items': [
    for (final id in ids)
      {
        'name': id == 1 ? '龍與後記' : '龍與後記 $id',
        'author': '自编作者',
        'kind': '女性視角',
        'bookUrl': '${request.source}/book/$id',
      },
  ],
  'hasMore': more,
  'pageUrl':
      request.url ?? '${request.source}/search/${request.key}/${request.page}',
  'nextUrl': next,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ChineseText.prepare);
  late Directory root;
  late SourceStore store;
  late SourceNovelRepository repository;
  late _SearchPlatform platform;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('source-search-variants-');
    store = SourceStore(File('${root.path}/index.json'));
    platform = _SearchPlatform();
    repository = SourceNovelRepository(store: store, platform: platform);
    await store.saveSources([fixtureSource()]);
  });
  tearDown(() async {
    repository.dispose();
    store.dispose();
    await root.delete(recursive: true);
  });

  test(
    'query variants retain exact input, convert both directions and leave Latin terms alone',
    () async {
      expect(await ChineseText.searchVariants('龙与后记'), ['龙与后记', '龍與後記']);
      final reverse = await ChineseText.searchVariants('龍與後記');
      expect(reverse.first, '龍與後記');
      expect(reverse, contains('龙与后记'));
      expect(ChineseText.searchKey('頭髮與發展'), '头发与发展');
      expect(await ChineseText.searchVariants('Open EPUB 2026'), [
        'Open EPUB 2026',
      ]);
      expect(await ChineseText.searchVariants('  '), isEmpty);
      expect(
        BookSearch(
          '龙与后记',
          field: BookSearchField.title,
        ).matches(title: '龍與後記', author: '', tags: ''),
        isTrue,
      );
      expect(
        BookSearch(
          '女性视角',
          field: BookSearchField.tags,
        ).matches(title: '', author: '', tags: '女性視角'),
        isTrue,
      );
    },
  );

  test(
    'simplified title finds a traditional-only source without changing book identity or metadata',
    () async {
      platform.reply = (r) async => _page(r, r.key == '龍與後記' ? [1] : []);
      final result = await repository.searchFilteredPage(
        '龙与后记',
        field: BookSearchField.title,
      );
      expect(result.items.single.title, '龍與後記');
      expect(result.items.single.bookUrl, '${fixtureSource().key}/book/1');
      expect(platform.requests.map((r) => r.key), ['龙与后记', '龍與後記']);
      expect(result.hasMore, isFalse);
      expect(store.books.single.title, '龍與後記');
    },
  );

  test(
    'literal results arrive first; later forms merge new books without duplicate rows',
    () async {
      platform.reply = (r) async => _page(r, r.key == '龙与后记' ? [1] : [1, 2]);
      final first = await repository.searchPage('龙与后记');
      expect(first.items, hasLength(1));
      expect(first.hasMore, isTrue);
      final second = await repository.searchPage('龙与后记', page: 2);
      expect(second.items.single.title, '龍與後記 2');
      expect(second.hasMore, isFalse);
      expect(store.books, hasLength(2));
      expect(second.items.single.id, isNot(first.items.single.id));
    },
  );

  test(
    'all-fields search rejects unrelated catalogue rows in either script',
    () async {
      platform.reply = (r) async => {
        ..._page(r, const []),
        'items': [
          for (var i = 0; i < 72; i++)
            {
              'name': i == 40 ? '龍與後記' : '自编作品 $i',
              'bookUrl': '${r.source}/book/$i',
            },
        ],
      };
      for (final word in ['龙与后记', '龍與後記']) {
        final result = await repository.searchFilteredPage(word);
        expect(result.items.map((b) => b.title), ['龍與後記']);
        expect(result.items.single.bookUrl, '${fixtureSource().key}/book/40');
      }
    },
  );

  test(
    'unrelated literal rows do not suppress the matching alternate form',
    () async {
      platform.reply = (r) async => r.key == '龙与后记'
          ? {
              ..._page(r, const []),
              'items': [
                {'name': '不相关的自编作品', 'bookUrl': '${r.source}/other'},
              ],
            }
          : _page(r, [1]);
      expect(
        (await repository.searchFilteredPage('龙与后记')).items.single.title,
        '龍與後記',
      );
      expect(platform.requests.map((r) => r.key), ['龙与后记', '龍與後記']);
    },
  );

  test(
    'unrelated pages remain bounded and can explicitly continue their cursors',
    () async {
      platform.reply = (r) async => r.page == 1
          ? {
              ..._page(
                r,
                const [],
                more: true,
                next: '${r.source}/next/${r.key}',
              ),
              'items': [
                {'name': '不相关的自编作品', 'bookUrl': '${r.source}/other'},
              ],
            }
          : _page(r, [1]);
      final first = await repository.searchFilteredPage('龙与后记');
      expect(first.items, isEmpty);
      expect(first.hasMore, isTrue);
      expect(platform.requests, hasLength(2));
      final second = await repository.searchFilteredPage('龙与后记', page: 2);
      expect(second.items.single.title, '龍與後記');
      expect(platform.requests.last.page, 2);
      expect(platform.requests.last.url, contains('/next/'));
    },
  );

  test(
    'each script form retains its own server cursor and source filter',
    () async {
      final other = fixtureSource('乙');
      await store.saveSources([other]);
      await repository.selectSearchSource(other.key);
      platform.reply = (r) async {
        final traditional = r.key == '龍與後記';
        return _page(
          r,
          [r.page == 1 ? (traditional ? 2 : 1) : (traditional ? 4 : 3)],
          more: r.page == 1,
          next: r.page == 1
              ? '${r.source}/cursor/${traditional ? 'traditional' : 'simplified'}'
              : null,
        );
      };
      final found = <int>[];
      for (var page = 1; page <= 4; page++) {
        final result = await repository.searchPage('龙与后记', page: page);
        found.addAll(result.items.map((b) => b.id));
        expect(result.hasMore, page != 4);
      }
      expect(found.toSet(), hasLength(4));
      expect(platform.requests.map((r) => (r.key, r.page)), [
        ('龙与后记', 1),
        ('龍與後記', 1),
        ('龙与后记', 2),
        ('龍與後記', 2),
      ]);
      expect(platform.requests.every((r) => r.source == other.key), isTrue);
      expect(platform.requests[2].url, '${other.key}/cursor/simplified');
      expect(platform.requests[3].url, '${other.key}/cursor/traditional');
    },
  );

  test(
    'one failed form does not suppress working forms or exceed source concurrency',
    () async {
      await store.saveSources([
        for (var i = 0; i < 7; i++) fixtureSource('source$i'),
      ]);
      platform.reply = (r) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (r.key == '龙与后记') {
          throw const SourceFailure('Synthetic request failure');
        }
        return _page(r, [1]);
      };
      final sources = <String>{};
      for (var page = 1; page <= 8; page++) {
        final result = await repository.searchPage('龙与后记', page: page);
        sources.addAll(result.items.map((b) => b.sourceId!));
        if (!result.hasMore) break;
      }
      expect(sources, hasLength(8));
      expect(platform.peak, lessThanOrEqualTo(3));
    },
  );

  test(
    'cancelled variant cannot overwrite the newer query or its paging state',
    () async {
      final started = Completer<void>(), blocked = Completer<void>();
      platform.reply = (r) async {
        if (r.key == '龙与后记') return _page(r, []);
        if (r.key == '龍與後記') {
          started.complete();
          await blocked.future;
        }
        return {
          ..._page(r, [1]),
          if (r.key == 'new')
            'items': [
              {'name': 'new', 'bookUrl': '${r.source}/new'},
            ],
        };
      };
      final old = repository.searchPage('龙与后记');
      await started.future;
      await repository.cancelSearch();
      final current = await repository.searchPage('new');
      expect(current.items, hasLength(1));
      blocked.complete();
      await expectLater(old, throwsA(isA<SourceFailure>()));
      expect((await repository.searchPage('new', page: 2)).items, isEmpty);
      expect(platform.cancellations, isNotEmpty);
    },
  );

  test(
    'empty literal response does not disguise a failed alternate query as no matches',
    () async {
      platform.reply = (r) async {
        if (r.key == '龙与后记') return _page(r, []);
        throw const SourceFailure('Synthetic alternate request failure');
      };
      await expectLater(
        repository.searchPage('龙与后记'),
        throwsA(
          isA<SourceFailure>().having(
            (e) => e.message,
            'message',
            'Synthetic alternate request failure',
          ),
        ),
      );
    },
  );

  test(
    'session completion invalidates failed searches and discovery choices',
    () async {
      final source = store.sources.single;
      await repository.explores(source);
      await repository.explores(source);
      expect(
        platform.calls.where((c) => c.contains(':explores:')),
        hasLength(1),
      );
      platform.reply = (r) async => throw const SourceFailure('书源要求登录');
      await expectLater(
        repository.searchPage('龙与后记'),
        throwsA(isA<SourceFailure>()),
      );
      expect(repository.failures, isNotEmpty);
      var notified = 0;
      repository.addListener(() => notified++);
      repository.sessionChanged();
      expect(notified, 1);
      expect(repository.failures, isEmpty);
      await repository.explores(source);
      expect(
        platform.calls.where((c) => c.contains(':explores:')),
        hasLength(2),
      );
      platform.reply = (r) async => _page(r, [1]);
      expect((await repository.searchPage('龙与后记')).items.single.title, '龍與後記');
    },
  );

  test(
    'discovery-only source explains missing search rules instead of reporting no matches',
    () async {
      await store.configure(
        BookSource({...fixtureSource().data, 'searchUrl': ''}),
      );
      await expectLater(
        repository.searchPage('example'),
        throwsA(
          isA<SourceFailure>().having(
            (e) => e.message,
            'message',
            contains('没有配置搜索规则'),
          ),
        ),
      );
      expect(platform.requests, isEmpty);
    },
  );
}
