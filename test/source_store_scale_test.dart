import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SourceStore store;
  final source = BookSource({
    'bookSourceUrl': 'https://fixture.invalid',
    'bookSourceName': '自编书源',
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('source-index-scale-');
    store = SourceStore(File('${root.path}/index.json'));
    await store.saveSources([source]);
  });
  tearDown(() async {
    store.dispose();
    await root.delete(recursive: true);
  });

  test(
    'large single-book directory persists without losing chapter identities',
    () async {
      final book = store.remember(source, {
        'bookUrl': '/one',
        'name': '长篇自编作品',
      });
      final chapters = [
        for (var i = 0; i < 12000; i++)
          {'name': '第 $i 章', 'url': 'https://fixture.invalid/chapter/$i'},
      ];
      await store.rememberChapters(book.id, chapters);
      final samples = <int>[];
      for (var i = 0; i < 3; i++) {
        final watch = Stopwatch()..start();
        final pending = store.flush();
        watch.stop();
        samples.add(watch.elapsedMicroseconds);
        await pending;
      }
      samples.sort();
      // This measures only the synchronous UI-isolate portion, not disk time or
      // device frame rate. Keep the complete data contract as the assertion.
      // ignore: avoid_print
      print('SOURCE_INDEX_12000_SYNC_US=${samples[1]}');
      final reopened = SourceStore(store.file);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.directory(book.id), hasLength(12000));
      expect(
        reopened.directory(book.id)!.last.id,
        store.directory(book.id)!.last.id,
      );
      expect(reopened.book(book.id)!.title, '长篇自编作品');
    },
  );

  test(
    'queued directory writes keep immutable per-request snapshots',
    () async {
      final book = store.remember(source, {'bookUrl': '/two', 'name': '自编作品'});
      final original = [
        for (var i = 1; i <= 640; i++)
          {'name': '第 $i 章', 'url': 'https://fixture.invalid/chapter/$i'},
      ];
      // Both writes exceed the background-encoding threshold and overlap.
      final first = store.rememberChapters(book.id, original);
      final second = store.rememberChapters(book.id, [
        {'name': '新序章', 'url': 'https://fixture.invalid/preface'},
        ...original,
      ]);
      await Future.wait([first, second]);
      final reopened = SourceStore(store.file);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.directory(book.id)!.map((c) => c.id), [
        641,
        for (var i = 1; i <= 640; i++) i,
      ]);
      await reopened.rememberChapters(book.id, [
        original.first,
        {'name': '新终章', 'url': 'https://fixture.invalid/epilogue'},
      ]);
      expect(reopened.directory(book.id)!.map((c) => c.id), [1, 642]);
    },
  );
}
