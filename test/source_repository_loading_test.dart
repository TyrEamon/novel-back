import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_platform.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_store.dart';

class _Choices extends SourcePlatform {
  final pending = <Completer<dynamic>>[];
  final cancelled = <String>[];
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
  }) {
    expect(operation, 'explores');
    final result = Completer<dynamic>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<void> cancel(String requestId) async => cancelled.add(requestId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SourceStore store;
  late _Choices platform;
  late SourceNovelRepository repository;
  final source = BookSource({
    'bookSourceName': '自编书源',
    'bookSourceUrl': 'https://fixture.invalid',
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('source-choices-');
    store = SourceStore(File('${root.path}/index.json'));
    await store.saveSources([source]);
    platform = _Choices();
    repository = SourceNovelRepository(store: store, platform: platform);
  });
  tearDown(() async {
    repository.dispose();
    store.dispose();
    await root.delete(recursive: true);
  });

  test(
    'concurrent discovery and chooser loads share one script execution',
    () async {
      final first = repository.explores(source);
      final second = repository.explores(source);
      expect(platform.pending, hasLength(1));
      platform.pending.single.complete([
        {'title': '自编分类', 'url': '/books'},
      ]);
      final lists = await Future.wait([first, second]);
      expect(identical(lists.first, lists.last), isTrue);
      expect((await repository.explores(source)).single.title, '自编分类');
      expect(platform.pending, hasLength(1));
    },
  );

  test(
    'a prior session cannot repopulate refreshed discovery choices',
    () async {
      final stale = repository.explores(source);
      final failed = expectLater(stale, throwsA(isA<SourceFailure>()));
      repository.sessionChanged();
      final fresh = repository.explores(source);
      expect(platform.pending, hasLength(2));
      expect(platform.cancelled, hasLength(1));
      platform.pending.first.complete([
        {'title': '旧分类', 'url': '/old'},
      ]);
      platform.pending.last.complete([
        {'title': '新分类', 'url': '/new'},
      ]);
      await failed;
      expect((await fresh).single.title, '新分类');
      expect(repository.exploreChoices.single.title, '新分类');
    },
  );

  test('selecting the current category does not invalidate the feed', () async {
    await store.select(source.key, '/books');
    var changes = 0;
    repository.addListener(() => changes++);
    await store.select(source.key, '/books');
    expect(changes, 0);
  });
}
