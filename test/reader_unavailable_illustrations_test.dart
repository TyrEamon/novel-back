import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_illustrations.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_pagination.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/sources/source_image_locator.dart';

final remote = sourceImageLocator(
  536870913,
  'https://fixture.invalid/image.jpg',
)!;
const local = 'wenku-local://1610612736/img-0.png';
final rows = [
  '<!--image-->$remote<!--image-->',
  '插图之后的第一段正文，仍然保持原有段落编号。',
  '第二段正文也要完整保留，不能因图片失败而丢失。',
];

Future<void> settleReader(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 16));
  for (var i = 0; i < 100; i++) {
    final paged = find.byType(ReaderPagedView);
    if (paged.evaluate().isEmpty ||
        tester.widget<ReaderPagedView>(paged).controller.ready) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 16));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'display exclusion keeps source text, image inventory and paragraph IDs',
    () {
      final original = ReaderContent(
        [...rows, '<!--image-->$local<!--image-->'],
        placementIds: const {0: 'original-placement'},
        inlineOwners: const {0: 1},
      );
      final shown = original.withoutUnavailableIllustrations({remote, local});
      expect(identical(shown.paragraphs, original.paragraphs), isTrue);
      expect(shown.order, [1, 2, 3]);
      expect(shown.inlineOwners, original.inlineOwners);
      expect(shown.placementIds, original.placementIds);
      expect(original.illustrations, [remote, local]);
      expect(shown.illustrations, [local]);
      expect(
        identical(original.withoutUnavailableIllustrations({}), original),
        isTrue,
      );
    },
  );

  testWidgets('inline failure reports once without a full-page error card', (
    tester,
  ) async {
    final failed = <String>[];
    final cache = ReaderIllustrationCache(
      request: (_) async => throw StateError('fixture unavailable'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderIllustration(
          url: remote,
          cache: cache,
          onUnavailable: failed.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(failed, [remote]);
    expect(find.text('插图加载失败'), findsNothing);
    expect(find.text('重试插图'), findsNothing);
    await tester.pump();
    expect(failed, [remote]);
  });

  testWidgets('explicit gallery view retains its retry action', (tester) async {
    final cache = ReaderIllustrationCache(
      request: (_) async => throw StateError('fixture unavailable'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderIllustration(url: remote, cache: cache),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('重试插图'), findsOneWidget);
  });

  for (final mode in ReaderMode.values) {
    testWidgets(
      '$mode omits the failed image page and continues with source text',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'readerChromeVisible': true,
          'readerChromeHintSeen': true,
          'reduceMotion': true,
        });
        final state = await LibraryState.load();
        await state.setReaderPreferences(ReaderPreferences(mode: mode));
        var requests = 0;
        ReaderIllustrationCache.shared.useResolver((_) async {
          requests++;
          throw StateError('fixture unavailable');
        });
        final book = Novel(
          id: 10345,
          title: '插图与正文',
          author: '',
          genre: '',
          summary: '',
          colors: const [Colors.black, Colors.grey],
          chapters: [NovelChapter('第一章', rows.join('\n\n'), id: 1001)],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: novelTheme(Brightness.light),
            home: ReaderPage(
              novel: book,
              state: state,
              repository: const DemoNovelRepository(),
              initialChapter: 0,
            ),
          ),
        );
        await settleReader(tester);
        expect(find.text('插图加载失败'), findsNothing);
        expect(find.byType(ReaderIllustration), findsNothing);
        expect(requests, 1);
        if (mode != ReaderMode.scroll) {
          final view = tester.widget<ReaderPagedView>(
            find.byType(ReaderPagedView),
          );
          expect(view.content.order, [1, 2]);
          expect(view.content.paragraphs, rows);
          expect(view.controller.anchor?.paragraph, 1);
        } else {
          expect(find.text(rows[1]), findsOneWidget);
          expect(find.text(rows[2]), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        ReaderIllustrationCache.shared.clearMemory();
      },
    );
  }
  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    testWidgets(
      '$mode lands on following text when a visible middle image fails',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'readerChromeVisible': true,
          'readerChromeHintSeen': true,
          'reduceMotion': true,
        });
        final state = await LibraryState.load();
        await state.setReaderPreferences(ReaderPreferences(mode: mode));
        final pending = Completer<Uint8List>();
        ReaderIllustrationCache.shared.useResolver((_) => pending.future);
        final body = ['图片之前的正文。', rows[0], rows[1]];
        final book = Novel(
          id: 10345,
          title: '插图与正文',
          author: '',
          genre: '',
          summary: '',
          colors: const [Colors.black, Colors.grey],
          chapters: [NovelChapter('第一章', body.join('\n\n'), id: 1001)],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: novelTheme(Brightness.light),
            home: ReaderPage(
              novel: book,
              state: state,
              repository: const DemoNovelRepository(),
              initialChapter: 0,
            ),
          ),
        );
        await settleReader(tester);
        var view = tester.widget<ReaderPagedView>(find.byType(ReaderPagedView));
        final before = view.controller.pageCount;
        view.controller.reveal(const ReaderTextAnchor(1, 0));
        await settleReader(tester);
        expect(view.controller.anchor?.paragraph, 1);
        pending.completeError(StateError('fixture unavailable'));
        await settleReader(tester);
        view = tester.widget<ReaderPagedView>(find.byType(ReaderPagedView));
        expect(view.content.order, [0, 2]);
        expect(view.content.paragraphs, body);
        expect(view.controller.anchor?.paragraph, 2);
        expect(view.controller.pageCount, lessThan(before));
        expect(find.byType(ReaderIllustration), findsNothing);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        ReaderIllustrationCache.shared.clearMemory();
      },
    );
  }
  testWidgets(
    'an illustration-only failed chapter continues without an empty image page',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'readerChromeVisible': true,
        'readerChromeHintSeen': true,
        'reduceMotion': true,
      });
      final state = await LibraryState.load();
      await state.setReaderPreferences(
        const ReaderPreferences(mode: ReaderMode.paged),
      );
      ReaderIllustrationCache.shared.useResolver(
        (_) async => throw StateError('fixture unavailable'),
      );
      final book = Novel(
        id: 10345,
        title: '插图与正文',
        author: '',
        genre: '',
        summary: '',
        colors: const [Colors.black, Colors.grey],
        chapters: [
          NovelChapter('插图', rows[0], id: 1001),
          NovelChapter('下一章', rows[1], id: 1002),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: ReaderPage(
            novel: book,
            state: state,
            repository: const DemoNovelRepository(),
            initialChapter: 0,
          ),
        ),
      );
      await settleReader(tester);
      final view = tester.widget<ReaderPagedView>(find.byType(ReaderPagedView));
      expect(view.title, '下一章');
      expect(view.content.paragraphs, [rows[1]]);
      expect(find.byType(ReaderIllustration), findsNothing);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      ReaderIllustrationCache.shared.clearMemory();
    },
  );
}
