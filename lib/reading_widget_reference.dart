import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'reading_widget_snapshot.dart';

/// Desktop widget sizes supported by the Android/iOS/HarmonyOS hosts.
enum ReadingDesktopSize {
  small('2x2'),
  medium('4x2'),
  large('4x4');

  const ReadingDesktopSize(this.caption);

  final String caption;

  double get width => this == ReadingDesktopSize.small ? 300 : 600;

  double get height => this == ReadingDesktopSize.large ? 600 : 300;
}

/// Preload any artwork the reference renderer needs. The placeholder renderer
/// paints flat colour only, so there is nothing to warm.
Future<void> warmReadingDesktopImages(ReadingWidgetSnapshot data) async {}

/// Render one widget face as PNG bytes.
Future<Uint8List> renderReadingDesktopCard(
  ReadingWidgetSnapshot data,
  ReadingDesktopSize size, {
  required Brightness brightness,
  bool paintQuote = true,
}) async {
  final width = size.width, height = size.height;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()
      ..color = brightness == Brightness.dark
          ? const Color(0xff141312)
          : const Color(0xfff6f1e7),
  );
  canvas.drawRect(
    Rect.fromLTWH(24, height - 96, width - 48, 1),
    Paint()..color = const Color(0x33807a6d),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width.round(), height.round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

/// Static preview used by the configuration page.
class ReadingDesktopCard extends StatelessWidget {
  const ReadingDesktopCard({
    super.key,
    required this.data,
    required this.size,
    required this.brightness,
    this.quoteText,
    this.quoteSource = '',
    this.quoteCount = 0,
  });

  final ReadingWidgetSnapshot data;
  final ReadingDesktopSize size;
  final Brightness brightness;
  final String? quoteText;
  final String quoteSource;
  final int quoteCount;

  @override
  Widget build(BuildContext context) {
    final dark = brightness == Brightness.dark;
    final text = quoteText?.trim();
    final minutes = (data.verifiedTodaySeconds ?? 0) ~/ 60;
    return AspectRatio(
      aspectRatio: size.width / size.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? const Color(0xff141312) : const Color(0xfff6f1e7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  text?.isNotEmpty == true ? text! : data.design.label,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: dark ? const Color(0xffe8e2d4) : const Color(0xff2b2a26),
                  ),
                ),
              ),
              Text(
                quoteSource.isEmpty ? '今日 $minutes 分钟' : quoteSource,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: dark ? const Color(0xff9d968a) : const Color(0xff7a7365),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}