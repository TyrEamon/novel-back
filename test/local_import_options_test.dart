import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/local_books.dart';
import 'package:wenku8_flutter/local_import_options.dart';
import 'package:wenku8_flutter/local_import_settings_page.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_pagination.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/sources/source_image_locator.dart';
import 'local_books_test.dart' show epubFixture;
import 'support/visual_review.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadReviewFonts();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'old cached Markdown wrappers do not consume prose or shift paragraph identities',
    () async {
      const image =
          '<!--image-->wenku-local://1610612736/img-0.png<!--image-->';
      final after = '插图之后的正文必须保留。' * 60;
      for (final suffix in ['', ')', ' "插图" )']) {
        final source = '前文。\n\n![图片](\n\n$image\n\n$suffix\n\n$after';
        final content = await ReaderContent.parse(source);
        expect(content.paragraphs.length, source.split('\n\n').length);
        expect(content.paragraphs.last, after);
        expect(content.illustrations, hasLength(1));
        expect(content.paragraphs.join(), isNot(contains('![图片](')));
        expect(
          content.paragraphs.indexOf(after),
          source.split('\n\n').indexOf(after),
        );
      }
    },
  );
  test(
    'old Markdown image query is restored without moving surrounding prose',
    () async {
      final locator = sourceImageLocator(
        536870913,
        'https://fixture.invalid/figure.jpg',
        referrer: 'https://fixture.invalid/chapter',
      )!;
      final image = '<!--image-->$locator<!--image-->';
      final source = '前文。\n\n![图片](\n\n$image\n\n?size=large&v=2)\n\n后文。';
      final content = await ReaderContent.parse(source);
      final restored = Uri.parse(content.illustrations.single);
      expect(
        restored.queryParameters['url'],
        'https://fixture.invalid/figure.jpg?size=large&v=2',
      );
      expect(
        restored.queryParameters['ref'],
        'https://fixture.invalid/chapter',
      );
      expect(content.paragraphs.length, source.split('\n\n').length);
      expect(content.paragraphs.first, '前文。');
      expect(content.paragraphs.last, '后文。');
      expect(content.paragraphs.join(), isNot(contains('?size=large&v=2)')));
      for (final complete in [
        'https://fixture.invalid/figure.jpg?existing=1',
        'https://fixture.invalid/figure.jpg,{"headers":{"X-Test":"value"}}',
      ]) {
        final original = sourceImageLocator(536870913, complete)!;
        final unchanged = await ReaderContent.parse(
          '![图片](\n\n<!--image-->$original<!--image-->\n\n?正文不能被删除)\n\n后文。',
        );
        expect(
          Uri.parse(unchanged.illustrations.single).queryParameters['url'],
          complete,
        );
        expect(unchanged.paragraphs.join(), contains('?正文不能被删除)'));
      }
    },
  );
  test(
    'TXT custom headings agree across streaming/byte paths and keep illustration-adjacent prose',
    () async {
      final before = '这是插图之前不可丢失的文字。' * 40;
      final after = '这是插图之后不可丢失的文字。' * 40;
      final text = '没有标题的前言。\n【第一节】\n$before\n[插图]\n$after\n【第二节】\n最后的正文。';
      const options = LocalImportOptions(chapterPattern: r'^【.+】$');
      final memory = parseLocalBook(
        LocalBookInput('目录.txt', Uint8List.fromList(utf8.encode(text))),
        options: options,
      );
      expect(memory.novel.chapters.map((c) => c.title), [
        '未命名章节 1',
        '【第一节】',
        '【第二节】',
      ]);
      expect(memory.bodies[1], '$before\n\n[插图]\n\n$after');
      final root = await Directory.systemTemp.createTemp('local-regex-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/book.txt');
      await file.writeAsString(text);
      final store = LocalBookStore(Directory('${root.path}/books'));
      await store.load();
      addTearDown(store.dispose);
      final imported = await store.importFile(
        '目录.txt',
        file.path,
        options: options,
      );
      expect(
        imported.chapters.map((c) => c.title),
        memory.novel.chapters.map((c) => c.title),
      );
      for (final (index, chapter) in imported.chapters.indexed) {
        expect(
          await store.chapterContent(imported.id, chapter),
          memory.bodies[index],
        );
      }
    },
  );
  test(
    'untitled EPUB chapters have an optional ordinal, without inventing a source heading',
    () {
      final bytes = epubFixture(
        overrides: {
          'OPS/book.opf':
              '<package><metadata><title>无标题书</title></metadata><manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/></spine></package>',
          'OPS/a.xhtml':
              '<html><body><p>原始正文。</p><img src="images/cover.png"/><p>插图后正文。</p></body></html>',
        },
      );
      final input = LocalBookInput('未命名.epub', bytes);
      expect(parseLocalBook(input).novel.chapters.single.title, '未命名章节 1');
      final numbered = parseLocalBook(
        input,
        options: const LocalImportOptions(generateMissingTitles: true),
      );
      expect(numbered.novel.chapters.single.title, '第 1 章');
      expect(numbered.bodies.single, isNot(contains('第 1 章')));
    },
  );
  test(
    'plain prose equal to a long nav label is not deleted before an illustration',
    () {
      final prose = '这是一段被目录误用的完整正文，必须保留。' * 30;
      final bytes = epubFixture(
        overrides: {
          'OPS/toc.ncx':
              '<ncx><navMap><navPoint><navLabel><text>$prose</text></navLabel><content src="a.xhtml"/></navPoint></navMap></ncx>',
          'OPS/a.xhtml':
              '<html><body><p>$prose</p><img src="images/cover.png"/><p>后面仍有正文。</p></body></html>',
        },
      );
      final book = parseLocalBook(LocalBookInput('原文.epub', bytes));
      expect(book.bodies.first, startsWith(prose));
      expect(book.bodies.first, endsWith('后面仍有正文。'));
      expect(
        ReaderContent(book.bodies.first.split('\n\n')).illustrations,
        hasLength(1),
      );
    },
  );
  test('regex EPUB split keeps every prose fragment and image in sequence', () {
    final before = '图前正文。' * 90, after = '图后正文。' * 90;
    final book = parseLocalBook(
      LocalBookInput(
        '分节.epub',
        epubFixture(
          overrides: {
            'OPS/a.xhtml':
                '<html><body><p>【第一节】</p><p>$before</p><img src="images/cover.png"/><p>$after</p><p>【第二节】</p><p>结尾。</p></body></html>',
          },
        ),
      ),
      options: const LocalImportOptions(chapterPattern: r'^【.+】$'),
    );
    expect(book.novel.chapters.take(2).map((c) => c.title), ['【第一节】', '【第二节】']);
    expect(book.bodies.first, startsWith(before));
    expect(book.bodies.first, endsWith(after));
    expect(
      ReaderContent(book.bodies.first.split('\n\n')).illustrations,
      hasLength(1),
    );
    expect(book.bodies[1], '结尾。');
  });
  test(
    'nonlinear spine text and image-adjacent content are available rather than dropped',
    () {
      final book = parseLocalBook(
        LocalBookInput(
          '附录.epub',
          epubFixture(
            overrides: {
              'OPS/book.opf':
                  '<package><metadata><title>附录</title></metadata><manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/><itemref idref="b" linear="no"/></spine></package>',
            },
          ),
        ),
      );
      expect(book.bodies.join(), contains('第二章正文。'));
    },
  );
  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    testWidgets(
      '$mode pagination conserves all text around mixed illustrations',
      (tester) async {
        final paragraphs = [
          for (var i = 0; i < 12; i++) '第$i段正文，插图前后的每一个字都应该保留。' * 25,
        ];
        paragraphs.insert(
          4,
          '<!--image-->wenku-local://1610612736/img-0.png<!--image-->',
        );
        final result = await tester.runAsync(
          () => paginateReader(
            content: ReaderContent(paragraphs),
            size: const Size(340, 580),
            style: const TextStyle(
              fontSize: 20,
              height: 1.7,
              fontFamily: 'Roboto',
            ),
            preferences: ReaderPreferences(mode: mode),
            scaler: TextScaler.noScaling,
            current: () => true,
          ),
        );
        for (final (index, text) in paragraphs.indexed) {
          final fragments = result!.pages
              .expand((page) => page.fragments)
              .where((f) => f.paragraph == index)
              .toList();
          expect(fragments.map((f) => f.text).join(), text);
        }
      },
    );
  }
  const deviceFixture = String.fromEnvironment('OPPO_READER_FIXTURE');
  if (deviceFixture.isNotEmpty) {
    for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
      testWidgets(
        'OPPO cached chapter retains every prose character in $mode',
        (tester) async {
          final content = (await tester.runAsync(
            () async =>
                ReaderContent.parse(await File(deviceFixture).readAsString()),
          ))!;
          for (final size in [const Size(350, 680), const Size(860, 560)]) {
            final pages = await tester.runAsync(
              () => paginateReader(
                content: content,
                size: size,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 22,
                  height: 1.72,
                ),
                preferences: ReaderPreferences(mode: mode),
                scaler: TextScaler.noScaling,
                current: () => true,
              ),
            );
            for (final (index, text) in content.paragraphs.indexed) {
              if (text.trim().isEmpty) continue;
              final actual = pages!.pages
                  .expand((leaf) => leaf.fragments)
                  .where((f) => f.paragraph == index)
                  .map((f) => f.text)
                  .join();
              expect(actual, text, reason: 'paragraph $index, $mode, $size');
            }
          }
        },
      );
    }
  }
  const epubFixturePath = String.fromEnvironment('OPPO_EPUB_FIXTURE');
  if (epubFixturePath.isNotEmpty) {
    test(
      'selected device EPUB retains source paragraphs through file import',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'device-epub-audit-',
        );
        addTearDown(() => root.delete(recursive: true));
        final store = LocalBookStore(Directory('${root.path}/books'));
        await store.load();
        addTearDown(store.dispose);
        final book = await store.importFile('检查样本.epub', epubFixturePath);
        final bodies = [
          for (final chapter in book.chapters)
            await store.chapterContent(book.id, chapter),
        ];
        String compact(String value) => value.replaceAll(RegExp(r'\s+'), '');
        final prose = compact(
          bodies
              .expand((body) => body.split('\n\n'))
              .where((p) => readerIllustrationUrl(p) == null)
              .join(),
        );
        final zip = ZipDecoder().decodeBytes(
          await File(epubFixturePath).readAsBytes(),
        );
        final files = {
          for (final file in zip.files.where((f) => f.isFile)) file.name: file,
        };
        String read(String path) =>
            utf8.decode(files[path]!.content as List<int>);
        final container = XmlDocument.parse(read('META-INF/container.xml'));
        final opfPath = container.descendants
            .whereType<XmlElement>()
            .firstWhere((e) => e.name.local == 'rootfile')
            .getAttribute('full-path')!;
        final opf = XmlDocument.parse(read(opfPath));
        final manifest = {
          for (final item in opf.descendants.whereType<XmlElement>().where(
            (e) => e.name.local == 'item',
          ))
            item.getAttribute('id'): item,
        };
        var cursor = 0, checked = 0, characters = 0;
        for (final ref in opf.descendants.whereType<XmlElement>().where(
          (e) => e.name.local == 'itemref',
        )) {
          final item = manifest[ref.getAttribute('idref')];
          if (item == null ||
              ![
                'application/xhtml+xml',
                'text/html',
              ].contains(item.getAttribute('media-type'))) {
            continue;
          }
          final path = Uri.parse(
            opfPath,
          ).resolve(item.getAttribute('href')!).path;
          final document = html.parse(read(path));
          for (final ignored in document.querySelectorAll(
            'script, style, nav, noscript',
          )) {
            ignored.remove();
          }
          for (final paragraph in document.body!.querySelectorAll('p')) {
            final expected = compact(paragraph.text);
            if (expected.isEmpty) continue;
            final at = prose.indexOf(expected, cursor);
            // Do not print private story text in a failing assertion or log.
            expect(
              at >= cursor,
              isTrue,
              reason: 'source paragraph $checked not retained in source order',
            );
            cursor = at + expected.length;
            checked++;
            characters += expected.length;
          }
        }
        expect(checked, greaterThan(0));
        debugPrint(
          'Device EPUB audit: ${book.chapters.length} chapters, $checked source paragraphs / $characters non-whitespace characters retained in order; ${bodies.expand((b) => b.split('\n\n')).where((p) => readerIllustrationUrl(p) != null).length} illustrations.',
        );
      },
    );
  }
  test(
    'directory preview validates syntax and kills pathological regex work',
    () async {
      expect(
        () => const LocalImportOptions(chapterPattern: '[').compile(),
        throwsFormatException,
      );
      expect(
        await previewLocalDirectory(
          const LocalImportOptions(chapterPattern: r'^【.+】$'),
          '前言\n【第一节】\n正文\n【第二节】',
        ),
        ['【第一节】', '【第二节】'],
      );
      await expectLater(
        previewLocalDirectory(
          const LocalImportOptions(chapterPattern: r'^(a+)+$'),
          '${'a' * 240}!',
        ),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'import options use shared controls, preview and persist explicit choices',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: novelTheme(Brightness.light, fontFamily: 'Roboto'),
            home: const LocalImportSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义正则'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, r'^【.+】$');
      await tester.ensureVisible(
        find.byKey(const ValueKey('preview-local-directory')),
      );
      await tester.tap(find.byKey(const ValueKey('preview-local-directory')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.text('匹配 2 个标题'), findsOneWidget);
      await captureReview(tester, capture, 'local-import-options');
      await tester.tap(find.byKey(const ValueKey('number-untitled-chapters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-local-import-options')));
      await tester.pumpAndSettle();
      final saved = await loadLocalImportOptions(
        await SharedPreferences.getInstance(),
      );
      expect(saved.chapterPattern, r'^【.+】$');
      expect(saved.generateMissingTitles, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
