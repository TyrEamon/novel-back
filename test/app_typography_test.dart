import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_typography.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_backup.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/listening/models.dart';
import 'package:wenku8_flutter/listening/store.dart';
import 'package:wenku8_flutter/main.dart';
import 'package:wenku8_flutter/reader_tools.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/user_fonts.dart';
import 'support/font_fixture.dart';
import 'cloud_library_ui_test.dart' show ioSettle;

Future<void> selectAppFont(
  WidgetTester tester,
  LibraryState state,
  String id,
) async {
  var complete = false;
  Object? failure;
  state
      .setAppFont(id)
      .then(
        (_) => complete = true,
        onError: (Object error) {
          failure = error;
          complete = true;
        },
      );
  // Reader position writes can already be queued in the fake frame zone.
  // Pump them while real file/font work completes instead of blocking that zone.
  await ioSettle(tester, until: () => complete);
  expect(failure, isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFontFixture);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'removed built-in face migrates to system while old backups and anchors survive',
    () async {
      SharedPreferences.setMockInitialValues({
        'appTypeface': 'sourceHanSerif',
        'readerTypeface': 'sourceHanSerif',
      });
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      expect(state.appTypeface, AppTypeface.system);
      final reloaded = await LibraryState.load();
      addTearDown(reloaded.dispose);
      expect(reloaded.appTypeface, AppTypeface.system);
      expect(reloaded.readerTypeface, 'system');
      expect(reloaded.readerFontFamily, isNull);
      await state.savePosition(
        novel: demoNovels.first,
        chapter: 0,
        offset: 100,
        maximum: 500,
        width: 390,
      );
      final position = state.positionFor(demoNovels.first.id)!;
      expect(position.typeface, 'system');
      expect(ReadingPosition.fromJson(position.toJson()).typeface, 'system');
      final legacy = position.toJson()..remove('typeface');
      expect(ReadingPosition.fromJson(legacy).typeface, 'system');
      final records = <String, Object>{
        'appTypeface': 'sourceHanSerif',
        'readerTypeface': 'sourceHanSerif',
        'reading_position_1': jsonEncode({
          ...position.toJson(),
          'typeface': 'sourceHanSerif',
        }),
      };
      final backup = await LibraryBackup.fromRecords(records);
      expect(
        (await LibraryBackup.parse(await backup.encode())).records,
        records,
      );
      await reloaded.restoreBackup(backup, importPreferences: true);
      expect(reloaded.appFontId, 'system');
      expect(reloaded.readerTypeface, 'system');
      expect(reloaded.positionFor(1)?.typeface, 'sourceHanSerif');
      await expectLater(
        LibraryBackup.fromRecords({'appTypeface': 'unknown'}),
        throwsFormatException,
      );
      await expectLater(
        LibraryBackup.fromRecords({
          'reading_position_1': jsonEncode({
            ...position.toJson(),
            'typeface': 'unknown',
          }),
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'all former offline selections fall back without synthesizing',
    () async {
      final voice = SpeechVoice(
        id: 'local',
        label: 'local',
        source: ListeningSource.system,
        engine: 'org.example.tts',
        offline: true,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('listening.voice.v1', jsonEncode(voice.toJson()));
      final store = ListeningStore(prefs);
      expect(store.voice, defaultEdgeVoice);
      await expectLater(store.saveVoice(voice), throwsA(isA<SpeechFailure>()));
    },
  );
  test(
    'text fonts are not bundled and remaining license assets are readable',
    () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(
        manifest.listAssets().where((p) => p.startsWith('assets/fonts/')),
        isEmpty,
      );
      expect(
        await rootBundle.loadString('assets/licenses/edge-tts.txt'),
        contains('LESSER GENERAL PUBLIC LICENSE'),
      );
    },
  );
  testWidgets(
    'switching the global typeface preserves the measured reader paragraph',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('typeface-switch-'),
      );
      addTearDown(() => root!.delete(recursive: true));
      final state = LibraryState(
        await SharedPreferences.getInstance(),
        fonts: UserFontStore(
          directory: Directory('${root!.path}/fonts'),
          loader: (_, _) async {},
        ),
      );
      final font = await tester.runAsync(() async {
        final file = await createFontFixture(root);
        return state.fonts.importFile('测试字体.otf', file.path);
      });
      final book = demoNovels.first.withChapters([
        NovelChapter(
          '字体测试',
          List.generate(
            100,
            (i) => '第 $i 段：${'阅读位置与字体变化一起保持。' * 6}',
          ).join('\n\n'),
        ),
      ]);
      await tester.pumpWidget(
        NovelApp(state: state, repository: const DemoNovelRepository()),
      );
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(HomeShell))).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(
            novel: book,
            state: state,
            repository: const DemoNovelRepository(),
            initialChapter: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('reader-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scroll.position.jumpTo(2400);
      await tester.pumpAndSettle();
      ParagraphPosition anchor() => tester
          .widget<ReaderParagraph>(find.byType(ReaderParagraph).first)
          .registry
          .capture(scroll.position.pixels + FrostedHeader.toolbarHeight + 12)!;
      final before = anchor();
      await selectAppFont(tester, state, font!.id);
      await tester.pumpAndSettle();
      expect(anchor().index, before.index);
      expect(anchor().fraction, closeTo(before.fraction, .02));
      expect(state.positionFor(book.id)!.typeface, font.id);
      await selectAppFont(tester, state, 'system');
      await tester.pumpAndSettle();
      expect(anchor().index, before.index);
      expect(anchor().fraction, closeTo(before.fraction, .02));
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
  testWidgets(
    'global font follows persisted switch and returns to the system',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('global-font-'),
      );
      addTearDown(() => root!.delete(recursive: true));
      final state = LibraryState(
        await SharedPreferences.getInstance(),
        fonts: UserFontStore(
          directory: Directory('${root!.path}/fonts'),
          loader: (_, _) async {},
        ),
      );
      final font = await tester.runAsync(() async {
        final file = await createFontFixture(root);
        return state.fonts.importFile('测试字体.otf', file.path);
      });
      await tester.pumpWidget(
        NovelApp(state: state, repository: const DemoNovelRepository()),
      );
      await tester.pumpAndSettle();
      final before = Theme.of(
        tester.element(find.text('发现').first),
      ).textTheme.bodyMedium!.fontFamily;
      await selectAppFont(tester, state, font!.id);
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.text('发现').first),
        ).textTheme.bodyMedium!.fontFamily,
        font.family,
      );
      await selectAppFont(tester, state, 'system');
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.text('发现').first),
        ).textTheme.bodyMedium!.fontFamily,
        before,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
  for (final cancel in [false, true]) {
    testWidgets(
      '${cancel ? 'cancelled' : 'quick'} typography drag commits the last preview exactly once',
      (tester) async {
        final committed = <double>[], previews = <double>[], phases = <bool>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReaderValueSlider(
                sliderKey: const ValueKey('slider'),
                label: '字号',
                value: 19,
                min: 15,
                max: 27,
                format: (v) => '$v',
                onCommitted: committed.add,
                onPreview: previews.add,
                onInteractionChanged: phases.add,
              ),
            ),
          ),
        );
        final rect = tester.getRect(find.byKey(const ValueKey('slider')));
        final gesture = await tester.startGesture(
          Offset(rect.left + rect.width / 3, rect.center.dy),
        );
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(80, 0));
        await tester.pump();
        expect(previews, isNotEmpty);
        expect(committed, isEmpty);
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pump();
        expect(committed, [previews.last]);
        expect(phases, [true, false]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
