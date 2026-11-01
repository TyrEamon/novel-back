import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'reading_widget_reference.dart';
import 'reading_widget_snapshot.dart';

/// Render every size/brightness face at once, keyed by "<size>_<brightness>".
Future<Map<String, Uint8List>> renderReadingDesktopCards(
  ReadingWidgetSnapshot data,
) async {
  final images = <String, Uint8List>{};
  for (final brightness in Brightness.values) {
    for (final size in ReadingDesktopSize.values) {
      images['${size.name}_${brightness.name}'] = await renderReadingDesktopCard(
        data,
        size,
        brightness: brightness,
      );
    }
  }
  return images;
}