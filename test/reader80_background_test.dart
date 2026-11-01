import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/book_documents.dart';
import 'package:wenku8_flutter/reader_background.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/reader_tools.dart';

import 'reader_modes_test.dart' as fixture;
import 'support/visual_review.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Documents extends BookDocuments {
  _Documents(this.selection);
  final BookDocumentSelection? selection;
  int released = 0;
  @override
  Future<BookDocumentSelection?> pickReaderBackground() async => selection;
  @override
  Future<void> releaseBooks(Iterable<BookDocumentSelection> books) async {
    released += books.length;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File original;
  late ReaderBackgroundStore store;
  late String id;
  late PathProviderPlatform previousPaths;
  setUpAll(() async {
    await loadReviewFonts();
    root = await Directory.systemTemp.createTemp('reader-background-test-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const rect = Rect.fromLTWH(0, 0, 390, 844);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff91b5bb), Color(0xffe8d4a5)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      const Offset(290, 180),
      115,
      Paint()..color = const Color(0xffe8ede6),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(390, 844);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    original = File('${root.path}/original.png');
    await original.writeAsBytes(data!.buffer.asUint8List());
    store = ReaderBackgroundStore(
      directory: Directory('${root.path}/reader-backgrounds'),
    );
    id = await store.importFile(original.path);
  });
  tearDownAll(() async {
    PathProviderPlatform.instance = previousPaths;
    await root.delete(recursive: true);
  });

  test(
    'old records, safe owned IDs and opacity round-trip without repagination',
    () {
      final old = ReaderPreferences.fromJson({'mode': 'paged'});
      expect(old.backgroundImage, null);
      final selected = old.copyWith(
        backgroundImage: id,
        backgroundOpacity: .35,
      );
      expect(selected.layoutKey, old.layoutKey);
      expect(ReaderPreferences.fromJson(selected.toJson()).backgroundImage, id);
      expect(
        ReaderPreferences.fromJson(selected.toJson()).backgroundOpacity,
        .35,
      );
      expect(selected.copyWith(clearBackground: true).backgroundImage, null);
      for (final invalid in [
        '../secret',
        '/sdcard/picture.png',
        'https://test/image',
        'bg_../bad',
      ]) {
        expect(
          () => ReaderPreferences.fromJson({'backgroundImage': invalid}),
          throwsFormatException,
        );
      }
      expect(
        () => ReaderPreferences.fromJson({'backgroundOpacity': 2}),
        throwsFormatException,
      );
    },
  );

  test(
    'private import survives the original disappearing; removal only deletes its own copy',
    () async {
      final source = await original.copy(
        '${root.path}/temporary-selection.png',
      );
      final own = await store.importFile(source.path);
      await source.delete();
      expect(await store.file(own), isNotNull);
      await store.remove(own);
      expect(await store.file(own), null);
      expect(await original.exists(), true);
      expect(await store.file('../original'), null);
      final bad = File('${root.path}/invalid.png');
      await bad.writeAsString('not a decoded PNG');
      await expectLater(store.importFile(bad.path), throwsFormatException);
      expect(
        (await root.list().toList()).where((f) => f.path.endsWith('.part')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'background selection, cancellation and removal keep originals intact',
    (tester) async {
      final state = await fixture.library(ReaderMode.scroll);
      addTearDown(state.dispose);
      final documents = _Documents(
        BookDocumentSelection(name: '背景.png', path: original.path),
      );
      Widget tools(BookDocuments picker) => MaterialApp(
        theme: novelTheme(Brightness.light),
        home: Scaffold(
          body: ReaderTools(
            novel: fixture.book,
            state: state,
            position: null,
            onAddBookmark: () async => null,
            onFontSize: (_) {},
            onLineHeight: (_) {},
            onReset: () {},
            backgrounds: store,
            documents: picker,
          ),
        ),
      );
      await tester.pumpWidget(tools(documents));
      await tester.pumpAndSettle();
      final choose = find.byKey(const ValueKey('reader-background-image'));
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      for (
        var i = 0;
        i < 15 && state.readerPreferences.backgroundImage == null;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final selected = state.readerPreferences.backgroundImage;
      expect(selected, isNotNull);
      expect(documents.released, 1);
      expect(find.text('更换背景图'), findsOneWidget);
      final canceled = _Documents(null);
      await tester.pumpWidget(tools(canceled));
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(state.readerPreferences.backgroundImage, selected);
      final remove = find.byKey(const ValueKey('reader-background-remove'));
      await tester.tap(remove);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(state.readerPreferences.backgroundImage, null);
      expect(await tester.runAsync(() => original.exists()), true);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'wallpaper stays in all reading modes; opacity does not relayout pages',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final state = await fixture.library(ReaderMode.paged);
      addTearDown(state.dispose);
      await state.setReaderChromeVisible(false);
      await state.setReaderPreferences(
        state.readerPreferences.copyWith(
          backgroundImage: id,
          backgroundOpacity: .35,
        ),
      );
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: capture, child: fixture.app(state)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await fixture.settleReader(tester);
      var decoded = false;
      final stream = FileImage(
        File('${root.path}/reader-backgrounds/$id.png'),
      ).resolve(const ImageConfiguration());
      final listener = ImageStreamListener((_, _) => decoded = true);
      stream.addListener(listener);
      for (var i = 0; i < 20 && !decoded; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      stream.removeListener(listener);
      expect(decoded, true);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<ReaderPagedView>(find.byType(ReaderPagedView))
          .controller;
      final generation = controller.debugLayoutGeneration;
      final retainedArticle = tester.element(
        find.byKey(const ValueKey('reader-content-tap')),
      );
      await state.setReaderPreferences(
        state.readerPreferences.copyWith(backgroundOpacity: .6),
      );
      await fixture.settleReader(tester);
      expect(controller.debugLayoutGeneration, generation);
      expect(
        tester.element(find.byKey(const ValueKey('reader-content-tap'))),
        same(retainedArticle),
      );
      for (final mode in ReaderMode.values) {
        await state.setReaderPreferences(
          state.readerPreferences.copyWith(mode: mode),
        );
        await fixture.settleReader(tester);
        expect(
          find.byKey(const ValueKey('reader-background-surface')),
          findsOneWidget,
        );
        await captureReview(
          tester,
          capture,
          'reader80-background-${mode.name}',
        );
        if (mode.paginated) {
          await state.setReduceMotion(false);
          await state.setReaderPreferences(
            state.readerPreferences.copyWith(
              pageEffect: ReaderPageEffect.cover,
            ),
          );
          await fixture.settleReader(tester);
          tester
              .widget<ReaderPagedView>(find.byType(ReaderPagedView))
              .controller
              .pageBy(1);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 160));
          await captureReview(
            tester,
            capture,
            'reader80-background-${mode.name}-cover',
          );
          await fixture.settleReader(tester);
        }
      }
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
