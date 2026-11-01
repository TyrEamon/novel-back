import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_pagination.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/reader_reflow.dart';
import 'support/reader_reflow_reference.dart' as before;

const _old = ReaderPageFragment(
  paragraph: 0,
  start: 0,
  end: 20,
  text: 'OLD / FIRST LINE\nSECOND LINE\nTHIRD LINE',
  rect: Rect.fromLTWH(0, 30, 280, 100),
);
const _new = ReaderPageFragment(
  paragraph: 0,
  start: 0,
  end: 30,
  text: 'NEW / FIRST LINE\nSECOND LINE\nTHIRD LINE\nFOURTH LINE',
  rect: Rect.fromLTWH(0, 0, 280, 140),
);
const _leaving = ReaderPageFragment(
  paragraph: 1,
  start: 0,
  end: 10,
  text: 'LEAVING / INK',
  rect: Rect.fromLTWH(0, 150, 280, 60),
);
Widget _text(ReaderPageFragment part) => Text(
  part.text,
  style: const TextStyle(fontSize: 18, height: 1.4, color: Colors.black),
);

Widget _scene(Animation<double> clock, {required bool reference}) {
  final parts = SizedBox(
    width: 300,
    height: 260,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: _new.rect,
          child: reference
              ? before.ReaderFragmentMotion(
                  fragment: _new,
                  index: 0,
                  count: 2,
                  previousBuilder: _text,
                  child: _text(_new),
                )
              : ReaderFragmentMotion(
                  fragment: _new,
                  index: 0,
                  count: 2,
                  previousBuilder: _text,
                  child: _text(_new),
                ),
        ),
        Positioned.fromRect(
          rect: _leaving.rect,
          child: reference
              ? before.ReaderLeavingFragment(
                  fragment: _leaving,
                  index: 1,
                  count: 2,
                  child: _text(_leaving),
                )
              : ReaderLeavingFragment(
                  fragment: _leaving,
                  index: 1,
                  count: 2,
                  child: _text(_leaving),
                ),
        ),
      ],
    ),
  );
  final viewport = reference
      ? before.ReaderIncrementalViewport(
          animation: clock,
          fromSize: const Size(300, 240),
          toSize: const Size(300, 260),
          originDelta: const Offset(0, 30),
          child: parts,
        )
      : ReaderIncrementalViewport(
          animation: clock,
          fromSize: const Size(300, 240),
          toSize: const Size(300, 260),
          originDelta: const Offset(0, 30),
          child: parts,
        );
  return reference
      ? before.ReaderReflowScope(
          animation: clock,
          previous: ReaderLeaf([_old, _leaving]),
          size: const Size(300, 260),
          previousSize: const Size(300, 240),
          originDelta: const Offset(0, 30),
          child: viewport,
        )
      : ReaderReflowScope(
          animation: clock,
          previous: ReaderLeaf([_old, _leaving]),
          size: const Size(300, 260),
          previousSize: const Size(300, 240),
          originDelta: const Offset(0, 30),
          child: viewport,
        );
}

void main() {
  testWidgets(
    'paint-only reflow retains the existing ink, clips and trajectory',
    (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clock = AnimationController(vsync: tester, value: 0);
      addTearDown(clock.dispose);
      Future<Uint8List> render(double t, bool reference) async {
        clock.value = t;
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: Colors.white,
                child: Center(child: _scene(clock, reference: reference)),
              ),
            ),
          ),
        );
        await tester.pump();
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        image.dispose();
        return bytes!.buffer.asUint8List();
      }

      for (final progress in [0.0, .18, .42, .73, 1.0]) {
        final old = await render(progress, true),
            current = await render(progress, false);
        expect(
          current,
          orderedEquals(old),
          reason: 'Original appearance at $progress',
        );
      }
      const sceneKey = ValueKey('only-reader-reflow');
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(key: sceneKey, child: _scene(clock, reference: false)),
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(sceneKey),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
        reason:
            'Shared reflow clock should not rebuild fragment/viewport widgets.',
      );
      for (var i = 0; i <= 120; i++) {
        clock.value = i / 120;
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    test(
      'image display filtering reuses ${mode.name} text measurements',
      () async {
        final source = ReaderContent(
          List.unmodifiable([
            'A long paragraph with unchanged text and stable paragraph identity. ' *
                8,
            '<!--image-->https://img.wenku8.com/fixture.jpg<!--image-->',
            'The following paragraph has stable text too. ' * 8,
          ]),
        );
        final cache = ReaderTextLayoutCache();
        Future<void> layout(ReaderContent content, double width) async {
          await paginateReader(
            content: content,
            size: Size(width, 500),
            style: const TextStyle(fontSize: 19, height: 1.72),
            preferences: ReaderPreferences(mode: mode),
            scaler: TextScaler.noScaling,
            current: () => true,
            cache: cache,
          );
        }

        await layout(source, 300);
        final shaped = cache.paragraphMeasurements;
        final filtered = source.withoutUnavailableIllustrations(
          source.illustrations.toSet(),
        );
        await layout(filtered, mode == ReaderMode.vertical ? 280 : 300);
        expect(cache.paragraphMeasurements, shaped);
      },
    );
  }
}
