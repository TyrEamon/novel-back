import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/book_search.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_store.dart';

import 'custom_sources_test.dart' show FixtureSourcePlatform, fixtureSource;

class CollectionPlatform extends FixtureSourcePlatform {
  final requests = <({String operation, String? url, String key, int page})>[];
  Completer<void>? collectionWait;
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
    requests.add((operation: operation, url: url, key: key, page: page));
    Map<String, Object?> item(int id) => {
      'bookUrl': '${source.key}/book/$id',
      'name': '作品$id',
      'author': '小舟',
    };
    if (operation == 'detail') {
      return {
        ...book!,
        'bookUrl': url,
        'authorUrl': '${source.key}/authors/7',
        'tagUrls': {'奇幻': '${source.key}/tags/3'},
      };
    }
    if (operation == 'explores') {
      return [
        {
          'title': '分类',
          'url': '',
          'style': {'layout_flexBasisPercent': 1},
        },
        {
          'title': '奇幻',
          'url': '${source.key}/tags/3',
          'style': {'layout_flexBasisPercent': .5},
        },
        {'title': '榜单', 'url': ''},
        {'title': '最新', 'url': '/new?page={{page}}'},
      ];
    }
    if (operation == 'search') {
      return {
        'items': [
          {...item(10), 'name': key},
        ],
        'hasMore': page == 1,
      };
    }
    if (operation == 'explore') {
      if (collectionWait != null) await collectionWait!.future;
      final target = url ?? '';
      if (target.endsWith('/authors/7')) {
        return {
          'items': [item(1), item(2)],
          'hasMore': true,
          'pageUrl': target,
          'nextUrl': '${source.key}/authors/7?cursor=2',
        };
      }
      if (target.endsWith('/authors/7?cursor=2')) {
        return {
          'items': [item(1), item(2)],
          'hasMore': true,
          'pageUrl': target,
          'nextUrl': '${source.key}/authors/7?cursor=3',
        };
      }
      if (target.endsWith('/authors/7?cursor=3')) {
        return {
          'items': [item(3)],
          'hasMore': false,
          'pageUrl': target,
        };
      }
      if (target.endsWith('/tags/3')) {
        return {
          'items': [item(4)],
          'hasMore': true,
          'pageUrl': target,
          'nextUrl': '${source.key}/tags/3?cursor=2',
        };
      }
      if (target.endsWith('/tags/3?cursor=2')) {
        return {
          'items': [item(5)],
          'hasMore': false,
          'pageUrl': target,
        };
      }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SourceStore store;
  late CollectionPlatform platform;
  late SourceNovelRepository repository;
  late BookSource source;
  late Novel book;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('source-collections-');
    store = SourceStore(File('${root.path}/index.json'));
    platform = CollectionPlatform();
    repository = SourceNovelRepository(store: store, platform: platform);
    source = fixtureSource();
    await store.saveSources([source]);
    book = store.remember(source, {
      'bookUrl': '${source.key}/book/1',
      'name': '作品1',
      'author': '小舟',
      'kind': '奇幻',
    });
    book = await repository.detail(book);
  });
  tearDown(() async {
    repository.dispose();
    store.dispose();
    await root.delete(recursive: true);
  });

  test(
    'related entry URLs persist across snapshots, list metadata and reloads',
    () async {
      final copied = Novel.fromSnapshot(
        book.toSnapshot(),
      ).withGenre('冒险').withChapters(const []);
      expect(copied.authorUrl, '${source.key}/authors/7');
      expect(copied.tagUrls, {'奇幻': '${source.key}/tags/3'});
      // Search/list rows don't overwrite the richer detail navigation metadata.
      store.remember(source, {'bookUrl': book.bookUrl, 'name': '作品1'});
      await store.flush();
      final reopened = SourceStore(store.file);
      await reopened.load();
      expect(reopened.book(book.id)!.authorUrl, copied.authorUrl);
      expect(reopened.book(book.id)!.tagUrls, copied.tagUrls);
      reopened.dispose();
      final old = Map<String, dynamic>.of(book.toSnapshot())
        ..remove('authorUrl')
        ..remove('tagUrls');
      expect(Novel.fromSnapshot(old).tagUrls, isEmpty);
    },
  );

  test(
    'author and tag collections use real server entries and independent cursors',
    () async {
      final author = SourceRelatedCollection(
        repository,
        origin: book,
        label: '小舟',
      );
      final tag = SourceRelatedCollection(
        repository,
        origin: book,
        label: '奇幻',
        tag: true,
      );
      final first = await author.page();
      expect(first.items.map((b) => b.title), ['作品1', '作品2']);
      expect(first.hasMore, isTrue);
      expect((await tag.page()).items.single.title, '作品4');
      // Ordinary search can change without cancelling or consuming related pages.
      await repository.searchPage('别的书');
      final second = await author.page(page: 2);
      expect(second.items.single.title, '作品3');
      expect(second.hasMore, isFalse);
      expect((await tag.page(page: 2)).items.single.title, '作品5');
      expect(
        platform.requests
            .where((r) => r.operation == 'search')
            .map((r) => r.key),
        ['别的书'],
      );
      expect(
        platform.requests
            .where((r) => r.url?.contains('/authors/') == true)
            .map((r) => r.page),
        [1, 2, 3],
      );
      // A newly opened author view starts at its own first page, not an old EOF.
      final reopened = SourceRelatedCollection(
        repository,
        origin: book,
        label: '小舟',
      );
      expect((await reopened.page()).items, hasLength(2));
      author.dispose();
      tag.dispose();
      reopened.dispose();
    },
  );

  test(
    'related disposal cancels its native request but keeps unrelated views usable',
    () async {
      final author = SourceRelatedCollection(
        repository,
        origin: book,
        label: '小舟',
      );
      platform.collectionWait = Completer<void>();
      final pending = author.page();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      author.dispose();
      expect(platform.cancellations, hasLength(1));
      platform.collectionWait!.complete();
      await expectLater(pending, throwsA(isA<SourceFailure>()));
      platform.collectionWait = null;
      expect((await repository.searchPage('星海')).items, isNotEmpty);
    },
  );
  test(
    'author/tag search uses collection endpoints, source selection and independent search modes',
    () async {
      final other = fixtureSource('乙');
      await store.saveSources([other]);
      final b = store.remember(other, {
        'bookUrl': '${other.key}/book/1',
        'name': '作品1',
        'author': '小舟',
        'kind': '奇幻',
      });
      await repository.detail(b);
      final authors = await repository.searchFilteredPage(
        '小舟',
        field: BookSearchField.author,
      );
      expect(authors.items, hasLength(4));
      expect(authors.items.map((b) => b.sourceId).toSet(), {
        source.key,
        other.key,
      });
      expect(
        (await repository.searchFilteredPage(
          '小舟',
          field: BookSearchField.author,
          page: 2,
        )).items,
        hasLength(2),
      );
      await repository.selectSearchSource(other.key);
      final tags = await repository.searchFilteredPage(
        '奇幻',
        field: BookSearchField.tags,
      );
      expect(tags.items.single.sourceId, other.key);
      expect(
        (await repository.searchFilteredPage(
          '奇幻',
          field: BookSearchField.tags,
          page: 2,
        )).items.single.title,
        '作品5',
      );
      expect(
        platform.requests.any(
          (r) => r.operation == 'search' && ['小舟', '奇幻'].contains(r.key),
        ),
        isFalse,
      );
    },
  );

  test(
    'category headings are not queries and categories preserve groups and layout',
    () async {
      final choices = await repository.explores(source);
      expect(choices.first.isHeading, isTrue);
      expect(choices[1].group, '分类');
      expect(choices[1].columnFraction, .5);
      expect(choices.last.group, '榜单');
      final first = await repository.tagPage('奇幻');
      expect(first.items.single.title, '作品4');
      expect(
        (await repository.tagPage('奇幻', page: 2)).items.single.title,
        '作品5',
      );
      await expectLater(
        repository.tagPage('不存在的标签'),
        throwsA(isA<SourceFailure>()),
      );
      expect(platform.requests.any((r) => r.operation == 'search'), isFalse);
    },
  );

  test(
    'corrected volume header never steals first chapter identity or counts as content',
    () async {
      final old = await store.rememberChapters(book.id, [
        {'name': '第一卷', 'url': '${source.key}/c1'},
        {'name': '第一话 出发', 'url': '${source.key}/c1'},
        {'name': '第二话 书店', 'url': '${source.key}/c2'},
      ]);
      final repaired = await store.rememberChapters(book.id, [
        {'name': '第一卷', 'url': '${source.key}/c1', 'isVolume': true},
        {'name': '第一话 出发', 'url': '${source.key}/c1', 'volumeTitle': '第一卷'},
        {'name': '第二话 书店', 'url': '${source.key}/c2', 'volumeTitle': '第一卷'},
        {'name': '第二卷', 'url': '${source.key}/c3', 'isVolume': true},
        {'name': '第三话 重逢', 'url': '${source.key}/c3', 'volumeTitle': '第二卷'},
      ]);
      expect(repaired.map((c) => c.title), ['第一话 出发', '第二话 书店', '第三话 重逢']);
      expect(repaired.first.id, old.first.id);
      expect(repaired[1].id, old[1].id);
      expect(store.book(book.id)!.chapterCount, 3);
      expect(NovelVolume.of(repaired).map((v) => v.length), [2, 1]);
      final reversed = await store.rememberChapters(book.id, [
        for (final c in repaired.reversed)
          {'name': c.title, 'url': c.url, 'volumeTitle': c.volumeTitle},
      ]);
      expect(reversed.first.id, repaired.last.id);
      expect(reversed.first.volumeTitle, '第二卷');
      expect(NovelVolume.of(reversed).map((v) => v.length), [1, 2]);
    },
  );
}
