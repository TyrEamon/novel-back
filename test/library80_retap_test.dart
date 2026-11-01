import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/local_books.dart';
import 'package:wenku8_flutter/network_status.dart';
import 'package:wenku8_flutter/offline_cache.dart';
import 'package:wenku8_flutter/offline_repository.dart';
import 'package:wenku8_flutter/pages.dart';
import 'support/visual_review.dart';

void main() {
  setUpAll(loadReviewFonts);
  testWidgets(
    'shelf/local retaps return smoothly without resetting books or filters',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'shelfLayout': 'list',
        'reduceMotion': false,
      });
      final state = await LibraryState.load();
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('library-retap-'),
      );
      final local = LocalBookStore(Directory('${root!.path}/books'));
      final cache = OfflineCacheStore(Directory('${root.path}/cache'));
      final network = NetworkStatus(initial: NetworkReachability.online);
      final repository = OfflineNovelRepository(
        remote: const DemoNovelRepository(),
        cache: cache,
        local: local,
        network: network,
      );
      for (var i = 0; i < 16; i++) {
        final book = Novel(
          id: 4000 + i,
          title: '书架书籍 $i',
          author: '作者',
          genre: '',
          summary: '',
          colors: const [Colors.grey, Colors.white],
        );
        await state.setShelfMembership(book.id, true, novel: book);
        await tester.runAsync(
          () => local.import(
            LocalBookInput(
              '本地书籍$i.txt',
              Uint8List.fromList(utf8.encode('第一章\n本地书籍正文$i。')),
            ),
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: HomeShell(
            state: state,
            repository: repository,
            network: network,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final index in [1, 2]) {
        await tester.tapAt(
          tester.getCenter(find.byKey(ValueKey('dock-tab-$index'))),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pumpAndSettle();
        final view = find.byKey(
          PageStorageKey(index == 1 ? 'shelf' : 'local-library'),
        );
        final retained = tester.element(view);
        await tester.drag(view, const Offset(0, -620));
        await tester.pumpAndSettle();
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: view, matching: find.byType(Scrollable)).first,
        );
        final offset = scroll.position.pixels;
        expect(offset, greaterThan(100));
        await tester.tapAt(
          tester.getCenter(find.byKey(ValueKey('dock-tab-$index'))),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(scroll.position.pixels, greaterThan(0));
        expect(scroll.position.pixels, lessThan(offset));
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, closeTo(0, .01));
        expect(tester.element(view), same(retained));
        await tester.drag(view, const Offset(0, -450));
        await tester.pumpAndSettle();
        await state.setReduceMotion(true);
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester.getCenter(find.byKey(ValueKey('dock-tab-$index'))),
        );
        await tester.pump();
        expect(scroll.position.pixels, closeTo(0, .01));
        await state.setReduceMotion(false);
        await tester.pumpAndSettle();
      }
      expect(local.books.length, 16);
      expect(state.shelf.length, 16);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
      repository.dispose();
      cache.dispose();
      local.dispose();
      network.dispose();
      state.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
}
